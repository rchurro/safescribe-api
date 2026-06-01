import structlog
import stripe as stripe_lib
from fastapi import APIRouter, Depends, Header, HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.dependencies import get_db, require_auth
from app.models.user import User

router = APIRouter()
logger = structlog.get_logger()
settings = get_settings()


@router.post("/checkout")
async def create_checkout_session(user: User = Depends(require_auth)):
    stripe_lib.api_key = settings.stripe_secret_key
    session = stripe_lib.checkout.Session.create(
        payment_method_types=["card"],
        line_items=[{"price": settings.stripe_price_id, "quantity": 1}],
        mode="subscription",
        success_url=settings.stripe_success_url,
        cancel_url=settings.stripe_cancel_url,
        customer_email=user.email,
        metadata={"user_id": str(user.id)},
    )
    return {"checkout_url": session.url}


@router.post("/webhook", include_in_schema=False)
async def stripe_webhook(
    request: Request,
    stripe_signature: str = Header(None, alias="stripe-signature"),
    db: AsyncSession = Depends(get_db),
):
    stripe_lib.api_key = settings.stripe_secret_key
    payload = await request.body()
    try:
        event = stripe_lib.Webhook.construct_event(payload, stripe_signature, settings.stripe_webhook_secret)
    except (ValueError, stripe_lib.SignatureVerificationError):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid webhook payload")

    if event["type"] == "checkout.session.completed":
        session_obj = event["data"]["object"]
        metadata = session_obj.metadata
        user_id = int(getattr(metadata, "user_id", 0)) if metadata else 0
        customer_id = session_obj.customer
        if user_id:
            result = await db.execute(select(User).where(User.id == user_id))
            user = result.scalar_one_or_none()
            if user:
                user.is_paid = True
                user.stripe_customer_id = customer_id
                await db.commit()
                logger.info("user.upgraded", user_id=user_id)

    return {"received": True}
