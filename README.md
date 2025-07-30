# 🍃 MongoDB Replica Set Installation Guide

การติดตั้ง MongoDB Replica Set แบบสมบูรณ์ พร้อม SSL/TLS Security สำหรับ Production Environment

## 📋 ข้อมูลระบบ

- **MongoDB Version:** 8.0.12 ARM64/AMD64
- **Operating System:** Ubuntu 20.04+ 
- **Replica Set Name:** rs0
- **SSL/TLS:** Production-grade certificates
- **Servers:** 3 nodes (1 Primary + 2 Secondary)

### 🖥️ Server Configuration

| Role | IP Address | Hostname | Port |
|------|------------|----------|------|
| Primary | 127.0.0.1 | mongodb1.demo.dev | 27017 |
| Secondary | 127.0.02 | mongodb2.demo.dev | 27017 |
| Secondary | 127.0.03 | mongodb3.demo.dev | 27017 |

### 🌐 DNS Configuration

- **SRV Record:** `_mongodb._tcp.database.demo.dev`
- **Domain:** `database.demo.dev`
- **Wildcard SSL:** `*.demo.dev`

---

## 🚀 Installation Process

### ⚡ Quick Installation (Recommended)

สำหรับการติดตั้งแบบเร็ว ใช้คำสั่งเดียวในแต่ละ server:

#### **Step 1: ติดตั้ง SSL Certificates ก่อน (ทุกเซิร์ฟเวอร์)**

```bash
# รันในทุกเซิร์ฟเวอร์ (127.0.0.1, 127.0.02, 127.0.03)
curl -fsSL https://raw.githubusercontent.com/vdohide/mongodb/refs/heads/main/create-ssl-certs.sh | sed 's/set -e/set +e/' | sudo -E bash -s "*.demo.dev,mongodb1.demo.dev,mongodb2.demo.dev,mongodb3.demo.dev,database.demo.dev" 127.0.0.1,127.0.02,127.0.03
```

**พารามิเตอร์:**
- `*.,mongodb1,mongodb2,mongodb3,database.demo.dev` = รายการ domains
- `127.0.0.1,127.0.02,127.0.03` = รายการ IP addresses

#### **Step 2: ติดตั้ง MongoDB (ทุกเซิร์ฟเวอร์)**

```bash
# รันในทุกเซิร์ฟเวอร์หลังจากติดตั้ง SSL เรียบร้อยแล้ว
curl -fsSL https://raw.githubusercontent.com/vdohide/mongodb/refs/heads/main/replica.sh | sed 's/set -e/set +e/' | sudo -E bash -s 127.0.0.1,127.0.02,127.0.03 admin 123456
```

**พารามิเตอร์:**
- `127.0.0.1,127.0.02,127.0.03` = รายการ IP ของ replica set
- `admin` = MongoDB admin username
- `123456` = MongoDB admin password

---

## 📝 Step-by-Step Installation

### **Prerequisites**

```bash
# อัพเดทระบบ
sudo apt update && sudo apt upgrade -y

# ติดตั้ง tools ที่จำเป็น
sudo apt install -y curl wget gnupg software-properties-common openssl
```

### **Step 1: SSL Certificate Installation**

#### **1.1 เข้าสู่ Server แต่ละตัว**

```bash
# Server 1 (Primary)
ssh root@127.0.0.1

# Server 2 (Secondary)
ssh root@127.0.02

# Server 3 (Secondary)
ssh root@127.0.03
```

#### **1.2 รัน SSL Installation Script**

ใน **ทุกเซิร์ฟเวอร์** รันคำสั่งนี้:

```bash
curl -fsSL https://raw.githubusercontent.com/zergolf1994/rental-repo/refs/heads/main/create-ssl-certs.sh | sed 's/set -e/set +e/' | sudo -E bash -s *.,mongodb1,mongodb2,mongodb3,database.demo.dev 127.0.0.1,127.0.02,127.0.03
```

#### **1.3 ตรวจสอบ SSL Installation**

```bash
# ตรวจสอบไฟล์ SSL
sudo ls -la /opt/mongodb/ssl/

# ตรวจสอบ certificate
sudo openssl x509 -in /opt/mongodb/ssl/mongodb.crt -text -noout | grep -E "(Subject:|DNS:|IP Address:)"
```

**Expected Output:**
```
Subject: C=TH, ST=Bangkok, L=Bangkok, O=VdoHide Ltd, OU=Database Team, CN=*.demo.dev
DNS:*.demo.dev
DNS:mongodb1.demo.dev
DNS:mongodb2.demo.dev
DNS:mongodb3.demo.dev
DNS:database.demo.dev
IP Address:127.0.0.1
IP Address:127.0.02
IP Address:127.0.03
```

### **Step 2: MongoDB Installation**

#### **2.1 รัน MongoDB Installation Script**

ใน **ทุกเซิร์ฟเวอร์** รันคำสั่งนี้:

```bash
curl -fsSL https://raw.githubusercontent.com/zergolf1994/rental-repo/refs/heads/main/install-mongodb-replica.sh | sed 's/set -e/set +e/' | sudo -E bash -s 127.0.0.1,127.0.02,127.0.03 admin 123456
```

#### **2.2 ตรวจสอบ MongoDB Service**

```bash
# ตรวจสอบสถานะ service
sudo systemctl status mongod

# ตรวจสอบ logs
sudo journalctl -u mongod --since "5 minutes ago" --no-pager

# ตรวจสอบการทำงาน
sudo mongosh --eval "db.runCommand('ping')"
```

### **Step 3: Replica Set Initialization**

#### **3.1 Initialize Replica Set (Primary Server เท่านั้น)**

รันใน **127.0.0.1** (Primary) เท่านั้น:

```bash
# Initialize replica set
sudo mongosh < /opt/mongodb/init-replica-set.js

# สร้าง admin user
sudo mongosh < /opt/mongodb/create-users.js
```

#### **3.2 ตรวจสอบ Replica Set Status**

```bash
# ตรวจสอบสถานะ replica set
sudo mongosh --eval "rs.status()"

# ตรวจสอบ members
sudo mongosh --eval "rs.status().members.forEach(m => print(m.name + ': ' + m.stateStr))"
```

**Expected Output:**
```
127.0.0.1:27017: PRIMARY
127.0.02:27017: SECONDARY
127.0.03:27017: SECONDARY
```

### **Step 4: SSL Configuration**

#### **4.1 อัพเดท MongoDB Configuration พร้อม SSL**

ใน **ทุกเซิร์ฟเวอร์**:

```bash
# หยุด MongoDB
sudo systemctl stop mongod

# อัพเดท configuration ด้วย SSL
sudo cp /opt/mongodb/ssl/mongod-ssl.conf /etc/mongod.conf

# เริ่ม MongoDB พร้อม SSL
sudo systemctl start mongod

# ตรวจสอบสถานะ
sudo systemctl status mongod
```

#### **4.2 ตรวจสอบ SSL Connection**

```bash
# ทดสอบ SSL connection
sudo /opt/mongodb/ssl/test-ssl-connection.sh

# ทดสอบการเชื่อมต่อด้วย TLS
mongosh "mongodb://admin:123456@database.demo.dev:27017/admin?replicaSet=rs0&authSource=admin&tls=true&tlsInsecure=true"
```

---

## 🔗 Connection Strings

### **Production SSL Connections**

#### **Basic SSL Connection**
```javascript
mongodb://admin:123456@database.demo.dev:27017/your_database?replicaSet=rs0&authSource=admin&tls=true&tlsInsecure=true
```

#### **Full Replica Set SSL Connection**
```javascript
mongodb://admin:123456@127.0.0.1:27017,127.0.02:27017,127.0.03:27017/your_database?replicaSet=rs0&authSource=admin&tls=true&tlsInsecure=true
```

#### **SRV Record Connection (Recommended)**
```javascript
mongodb+srv://admin:123456@database.demo.dev/your_database?authSource=admin&tls=true&tlsInsecure=true
```

#### **High Security Connection (Certificate Validation)**
```javascript
mongodb://admin:123456@database.demo.dev:27017/your_database?replicaSet=rs0&authSource=admin&tls=true&tlsCertificateKeyFile=/opt/mongodb/ssl/mongodb.pem&tlsCAFile=/opt/mongodb/ssl/ca-bundle.crt
```

### **Application Examples**

#### **Node.js (Mongoose)**
```javascript
const mongoose = require('mongoose');

const connectionString = 'mongodb://admin:123456@database.demo.dev:27017/vdohide_production?replicaSet=rs0&authSource=admin&tls=true&tlsInsecure=true';

mongoose.connect(connectionString, {
  useNewUrlParser: true,
  useUnifiedTopology: true,
  maxPoolSize: 10,
  serverSelectionTimeoutMS: 5000,
  socketTimeoutMS: 45000,
});
```

#### **Python (PyMongo)**
```python
from pymongo import MongoClient

client = MongoClient(
    'mongodb://admin:123456@database.demo.dev:27017/vdohide_production?replicaSet=rs0&authSource=admin&tls=true&tlsInsecure=true',
    maxPoolSize=50,
    serverSelectionTimeoutMS=5000
)

db = client['vdohide_production']
```

#### **PHP (MongoDB Driver)**
```php
<?php
$connectionString = 'mongodb://admin:123456@database.demo.dev:27017/vdohide_production?replicaSet=rs0&authSource=admin&tls=true&tlsInsecure=true';

$client = new MongoDB\Client($connectionString, [
    'maxPoolSize' => 100,
    'serverSelectionTimeoutMS' => 5000
]);

$database = $client->selectDatabase('vdohide_production');
?>
```

---

## 🔧 Post-Installation Configuration

### **Health Monitoring**

```bash
# ตรวจสอบ replica set health
sudo /opt/mongodb/health-check.sh

# ตรวจสอบ performance
sudo mongosh --eval "db.serverStatus().connections"
sudo mongosh --eval "db.serverStatus().wiredTiger.cache"
```

### **Backup Setup**

```bash
# ตั้งค่า automated backup (ทุกเซิร์ฟเวอร์)
sudo crontab -e

# เพิ่มบรรทัดนี้สำหรับ backup ทุกคืนเวลา 2:00 AM
0 2 * * * /opt/mongodb/backup.sh
```

### **Log Rotation**

```bash
# ตั้งค่า log rotation
sudo nano /etc/logrotate.d/mongodb

# เพิ่มเนื้อหา:
/var/log/mongodb/*.log {
    daily
    missingok
    rotate 52
    compress
    notifempty
    create 644 mongodb mongodb
    postrotate
        /bin/kill -USR1 `cat /var/run/mongodb/mongod.pid 2> /dev/null` 2> /dev/null || true
    endscript
}
```

---

## 🛠️ Troubleshooting

### **Common Issues**

#### **1. MongoDB ไม่สามารถเริ่มได้**
```bash
# ตรวจสอบ logs
sudo journalctl -u mongod --since "10 minutes ago" --no-pager

# ตรวจสอบ configuration
sudo mongod --config /etc/mongod.conf --verbose

# ตรวจสอบ permissions
sudo chown -R mongodb:mongodb /var/lib/mongodb
sudo chown -R mongodb:mongodb /var/log/mongodb
sudo chown mongodb:mongodb /etc/mongod.conf
```

#### **2. SSL Connection Issues**
```bash
# ทดสอบ certificate
sudo openssl x509 -in /opt/mongodb/ssl/mongodb.crt -text -noout

# ทดสอบ SSL connection
openssl s_client -connect database.demo.dev:27017 -servername database.demo.dev

# ตรวจสอบ DNS resolution
nslookup database.demo.dev
```

#### **3. Replica Set Connection Problems**
```bash
# ตรวจสอบ network connectivity
ping 127.0.0.1
telnet 127.0.0.1 27017

# ตรวจสอบ firewall
sudo ufw status

# ตรวจสอบ replica set configuration
sudo mongosh --eval "rs.conf()"
```

### **Performance Optimization**

#### **MongoDB 8.0.12 Optimizations**
```bash
# ตรวจสอบ WiredTiger cache
sudo mongosh --eval "db.serverStatus().wiredTiger.cache"

# ตรวจสอบ compression
sudo mongosh --eval "db.runCommand({serverStatus:1}).compression"

# ตรวจสอบ connections
sudo mongosh --eval "db.serverStatus().connections"
```

#### **System Optimizations**
```bash
# ตรวจสอบ system limits
ulimit -n
ulimit -u

# ตรวจสอบ transparent huge pages
cat /sys/kernel/mm/transparent_hugepage/enabled
```

---

## 📊 Monitoring & Maintenance

### **Daily Health Checks**

```bash
# รัน health check script
sudo /opt/mongodb/health-check.sh

# ตรวจสอบ disk usage
df -h /var/lib/mongodb

# ตรวจสอบ memory usage
free -h
```

### **Weekly Maintenance**

```bash
# ตรวจสอบ replica set lag
sudo mongosh --eval "rs.printReplicationInfo()"

# ทดสอบ backup restore
sudo /opt/mongodb/backup.sh

# ตรวจสอบ SSL certificate expiry
sudo openssl x509 -in /opt/mongodb/ssl/mongodb.crt -noout -dates
```

---

## 🎯 Summary

ระบบ MongoDB Replica Set ที่ติดตั้งเสร็จจะมี:

- ✅ **MongoDB 8.0.12** พร้อม ARM64/AMD64 support
- ✅ **SSL/TLS Encryption** สำหรับ production security
- ✅ **3-Node Replica Set** สำหรับ high availability
- ✅ **Performance Optimization** สำหรับ production workload
- ✅ **Automated Backup** และ monitoring scripts
- ✅ **DNS SRV Record** support
- ✅ **Firewall Configuration** สำหรับ security

### **Key Features:**

1. **High Availability:** 3-node replica set with automatic failover
2. **Security:** SSL/TLS encryption, authentication, authorization
3. **Performance:** WiredTiger compression, optimized cache settings
4. **Monitoring:** Health check scripts, automated backups
5. **Scalability:** Ready for production workloads

### **Connection Information:**

- **Domain:** `database.demo.dev`
- **Admin User:** `admin`
- **Password:** `123456`
- **Replica Set:** `rs0`
- **SSL:** Required for production connections

สำหรับการใช้งานใน production environment ควรเปลี่ยนรหัสผ่าน admin และตั้งค่า monitoring เพิ่มเติมตามความต้องการของระบบ
