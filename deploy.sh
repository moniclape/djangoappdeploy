#!/bin/bash

GIT_REPO="https://github.com/DireSky/OSEExam.git"
APP_NAME="OSEExam"
APP_DIR="/var/www/$APP_NAME/testPrj"
PYTHON="python3.13"
DATE=$(date +"%Y-%m-%d_%H-%M-%S")
PORT=8002

LOG="/var/log/deploying.log"
echo "Django app starting: $DATE" >> $LOG

if [ "$(id -u)" -ne 0 ]; then
  echo "Run the command with sudo" | tee -a $LOG
  exit 1
fi

apt update && apt install -y $PYTHON $PYTHON-venv git curl net-tools || {
  echo "Package installation error" | tee -a $LOG
  exit 1
}

if [ ! -d "$APP_DIR" ]; then
  git clone $GIT_REPO $APP_DIR || {
    echo "Cloning git repo error" | tee -a $LOG
    exit 1
  }
else
  echo "Dir $APP_DIR already exists" | tee -a $LOG
fi

cd $APP_DIR || exit

if [ ! -d "venv" ]; then
  $PYTHON -m venv venv || {
    echo "Error creating virtual environment" | tee -a $LOG
    exit 1
  }
fi

source venv/bin/activate

if [ -f "requirements.txt" ]; then
  pip install -r requirements.txt || {
    echo "Dependency installation error" | tee -a $LOG
    deactivate
    exit 1
  }
else
  echo "requirements.txt not found" | tee -a $LOG
fi

deactivate

source venv/bin/activate
python manage.py migrate || {
  echo "Migration execution error" | tee -a $LOG
  deactivate
  exit 1
}
python manage.py collectstatic --noinput || {
  echo "Static files build error" | tee -a $LOG
  deactivate
  exit 1
}
deactivate

SETTINGS_FILE="$APP_DIR/testPrj/settings.py"

if ! grep -q "whitenoise.middleware.WhiteNoiseMiddleware" "$SETTINGS_FILE"; then
  echo "Adding WhiteNoise middleware to settings.py" | tee -a $LOG
  sed -i "/'django.middleware.security.SecurityMiddleware'/a \ \ \ \ 'whitenoise.middleware.WhiteNoiseMiddleware'," "$SETTINGS_FILE"
  echo -e "\n# WhiteNoise settings" >> "$SETTINGS_FILE"
  echo "STATICFILES_STORAGE = 'whitenoise.storage.CompressedManifestStaticFilesStorage'" >> "$SETTINGS_FILE"
  echo "STATIC_ROOT = os.path.join(BASE_DIR, 'static')" >> "$SETTINGS_FILE"
fi

if ! grep -q "ALLOWED_HOSTS" "$SETTINGS_FILE"; then
  echo "Adding ALLOWED_HOSTS to settings.py" | tee -a $LOG
  echo -e "\n# ALLOWED_HOSTS settings" >> "$SETTINGS_FILE"
  echo "ALLOWED_HOSTS = ['localhost', '127.0.0.1', '0.0.0.0', '*']" >> "$SETTINGS_FILE"
fi

if ! grep -q "STATIC_ROOT" "$SETTINGS_FILE"; then
  echo "Adding STATIC_ROOT to settings.py" | tee -a $LOG
  echo "STATIC_ROOT = os.path.join(BASE_DIR, 'static')" >> "$SETTINGS_FILE"
fi

free_port() {
  PID=$(netstat -ltnp | grep ":$PORT " | awk '{print $7}' | cut -d'/' -f1)
  if [ ! -z "$PID" ]; then
    echo "Port $PORT is occupied by a process with PID $PID" | tee -a $LOG
    kill -9 $PID || {
      echo "Failed to terminate the process using port $PORT" | tee -a $LOG
      exit 1
    }
    echo "Process with PID $PID using port $PORT has been terminated" | tee -a $LOG
  else
    echo "Port $PORT is free" | tee -a $LOG
  fi
}

free_port $PORT
start_gunicorn() {
  MAX_ATTEMPTS=3
  attempt=0
  while [ $attempt -lt $MAX_ATTEMPTS ]; do
    ((attempt++))
    source venv/bin/activate
    echo "Running Gunicorn attempt #$attempt..." | tee -a $LOG
    $APP_DIR/venv/bin/gunicorn --workers 3 --bind localhost:$PORT testPrj.wsgi:application || {
      echo "Gunicorn terminated with an error. Attempt #$attempt failed. Restarting..." | tee -a $LOG
    }
    deactivate
    if [ $attempt -lt $MAX_ATTEMPTS ]; then
      sleep 3
    fi
  done

  if [ $attempt -ge $MAX_ATTEMPTS ]; then
    echo "Gunicorn failed to start after $MAX_ATTEMPTS attempts. Exiting..." | tee -a $LOG
    exit 1
  fi
}

export PYTHONPATH=$APP_DIR/testPrj:$PYTHONPATH
start_gunicorn &
APP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$PORT)
echo "You can check this url: http://localhost:$PORT  or  http://127.0.0.1:$PORT"

if [ "$APP_STATUS" -eq 200 ]; then
  echo "The application has been successfully deployed and is available at http://localhost:$PORT" | tee -a $LOG
else
  echo "Error: The application is not available. Check the settings" | tee -a $LOG
fi

exit 0

#chmod +x <название файла>.sh
#./<название файла>.sh                                              (sudo)


#чтобы выключить скрипт напишите                                    ps aux | grep gunicorn
#далле найдите PID (числа после root) скопируйте и напишите         kill <PID>
