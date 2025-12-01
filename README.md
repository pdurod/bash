📡 qrz_lookup.sh

A lightweight Bash script that performs ham radio callsign lookups using the QRZ XML API, with automatic session caching and optional CSV/JSON export.

This tool is ideal for amateur radio operators who want fast, local command-line lookups without needing a browser.

⸻

🔧 Features
	•	🔑 Automatic QRZ session caching
	•	Sessions stored for 60 minutes
	•	Automatically refreshes expired or invalid sessions
	•	🔍 Callsign lookup via QRZ XML API
	•	📦 Export results to CSV or JSON
	•	🛠️ Cross-platform compatible (macOS & Linux)
	•	🎯 Error handling for invalid or expired sessions
	•	🗂️ Maintains growing log files:
	•	qrz_callsigns.csv
	•	qrz_callsigns.json

⸻

📥 Requirements

qrz_lookup.sh requires:
	•	bash (compatible with macOS or Linux)
	•	curl
	•	jq (only required for --json support)
	•	A QRZ.com XML API subscription (required to get a session key)

⸻

🚀 Installation

git clone https://github.com/yourusername/qrz-lookup.git
cd qrz-lookup
chmod +x qrz_lookup.sh

🔑 QRZ Login Setup

The first time you run the script — or when your session expires — it will ask for:

QRZ username:
QRZ password:

The script securely stores only the temporary session key in a local file:

.qrz_session

Passwords are not stored.

Example:

./qrz_lookup.sh N8CUB

⭐ Export Options

+----------------------+-----------------------------------------------+
| Option               | Description                                   |
+----------------------+-----------------------------------------------+
| --csv                | Append lookup to qrz_callsigns.csv            |
| --json               | Append lookup to qrz_callsigns.json           |
| --both / --csvjson   | Export to both CSV and JSON                   |
+----------------------+-----------------------------------------------+
