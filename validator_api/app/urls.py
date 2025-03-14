from django.urls import path
from .views import Calculate
from .views import StoreFile

urlpatterns = [
    path('calculate', Calculate.as_view(), name='calculate'),
    path('store-file', StoreFile.as_view(), name='store_file'),
]