from typing import Annotated, Optional

from fastapi import APIRouter, Depends

from app.constants.webllm import ALL_MODEL_IDS, FREE_MODEL_ID
from app.dependencies import get_current_user
from app.models.user import User
from app.schemas.models import ModelListResponse

router = APIRouter()


@router.get("", response_model=ModelListResponse)
async def list_models(
    current_user: Annotated[Optional[User], Depends(get_current_user)],
):
    is_paid = bool(current_user and current_user.is_paid)
    return ModelListResponse(models=ALL_MODEL_IDS, is_paid=is_paid)
