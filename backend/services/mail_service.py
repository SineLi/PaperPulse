import os
import logging
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart


logger = logging.getLogger(__name__)

def send_verification_email(to_email: str, code: str) -> None:
    # Load SMTP configuration from environment variables
    SMTP_SERVER = os.getenv("SMTP_SERVER")
    SMTP_PORT = int(os.getenv("SMTP_PORT", 587))
    SMTP_USERNAME = os.getenv("SMTP_USERNAME")
    SMTP_KEY = os.getenv("SMTP_KEY")
    SOURCE_EMAIL = os.getenv("SOURCE_EMAIL", SMTP_USERNAME)

    if not all([SMTP_SERVER, SMTP_PORT, SMTP_USERNAME, SMTP_KEY]):
        logger.error("SMTP configuration is incomplete. Please check environment variables.")
        raise RuntimeError("SMTP configuration is incomplete")
    
    msg = MIMEMultipart()
    msg = MIMEMultipart("alternative")
    msg["Subject"] = "您的PaperPulse验证码"
    msg["From"] = str(SOURCE_EMAIL)
    msg["To"] = to_email
   

    # Create the email content
    text = f"您的验证码是：{code}"
    # HTML 版本（推荐，便于样式控制）
    html = f"""\
    <html>
      <body>
        <p>您的验证码是：<strong>{code}</strong></p>
        <p>验证码有效期为30分钟</p>
        <p>请勿将此验证码泄露给他人。</p>
      </body>
    </html>
    """
    msg.attach(MIMEText(text, "plain"))
    msg.attach(MIMEText(html, "html"))


    try:
        # Connect to the SMTP server and send the email
        with smtplib.SMTP(str(SMTP_SERVER), SMTP_PORT) as server:
            server.starttls()
            server.login(str(SMTP_USERNAME), str(SMTP_KEY))
            server.send_message(msg)
        logger.info(f"Verification email sent to {to_email}")
    except Exception as e:
        logger.error(f"Failed to send verification email: {e}")
        raise RuntimeError("Failed to send verification email") from e
