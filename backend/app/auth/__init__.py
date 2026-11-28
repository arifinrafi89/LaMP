"""Phone sign-in and sessions (build plan D2, 2.1, 3.2 and G3).

A Banglalink number and one Applink OTP per device (applink/otp.py), then LaMP's own
session: a 15-minute access token and a rotating 30-day refresh token (tokens.py,
sessions.py). `deps.current_owner` is what every owner route depends on.
"""
