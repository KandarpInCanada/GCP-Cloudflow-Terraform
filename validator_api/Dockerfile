FROM python:3.9-slim
EXPOSE 6000
WORKDIR /validator_api
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
ENV PYTHONUNBUFFERED=1
ENV DJANGO_SETTINGS_MODULE=validator_api.settings
CMD ["python", "manage.py", "runserver", "0.0.0.0:6000"]