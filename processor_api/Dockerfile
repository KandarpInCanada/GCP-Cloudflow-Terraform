FROM python:3.9-slim
WORKDIR /processor_api
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 6001
ENV PYTHONUNBUFFERED=1
ENV DJANGO_SETTINGS_MODULE=processor_api.settings
CMD ["python", "manage.py", "runserver", "0.0.0.0:6001"]