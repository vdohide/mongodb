# หยุด MongoDB
sudo systemctl stop mongod


# เริ่ม MongoDB ใหม่
sudo systemctl start mongod

# รีสตาร์ท MongoDB 
sudo systemctl restart mongod

# ตรวจสอบสถานะ
sudo systemctl status mongod

# ดู startup logs
sudo journalctl -u mongod --since "5 minutes ago" --no-pager

# ตรวจหา success messages
sudo grep -E "(Successfully|started|listening)" /var/log/mongodb/mongod.log | tail -10

# ตรวจหา error messages
sudo grep -E "(ERROR|WARN|Failed)" /var/log/mongodb/mongod.log | tail -10