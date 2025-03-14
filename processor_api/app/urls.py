from django.urls import path
from .views import ProcessTheData

urlpatterns = [
    path('process', ProcessTheData.as_view(), name='process_the_data'),
]