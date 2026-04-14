# Drive Safe

Systeme de detection de fatigue du conducteur en temps reel avec Python, OpenCV et MediaPipe.

## Fonctionnalites

- Detection des yeux fermes avec EAR
- Detection du baillement avec MAR
- Detection de l'inclinaison laterale de la tete
- Detection de la chute de la tete vers l'avant
- Score de fatigue en temps reel de 0 a 100
- Alarme sonore
- Notification email optionnelle
- Journalisation CSV des alertes

## Lancement

```powershell
python -m pip install -r requirements.txt
python detection.py
```

## Configuration email

Le projet peut fonctionner sans email.

Si vous voulez activer l'alerte email, copiez `config.example.py` en `config.py` puis renseignez vos identifiants Gmail.
