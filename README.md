# คู่มือการติดตั้ง MongoDB Replica Set

## ภาพรวม

คู่มือนี้ให้คำแนะนำทีละขั้นตอนสำหรับการติดตั้ง MongoDB Replica Set โดยใช้สคริปต์ติดตั้งอัตโนมัติที่สามารถดำเนินการต่อแม้เจอข้อผิดพลาดและกำหนดค่า IP addresses ที่ระบุ

## ข้อกำหนดเบื้องต้น

- เซิร์ฟเวอร์ Ubuntu 3 เครื่อง (ขั้นต่ำ)
- สิทธิ์ Root หรือ sudo บนเซิร์ฟเวอร์ทุกเครื่อง
- การเชื่อมต่อเครือข่ายระหว่างเซิร์ฟเวอร์ทุกเครื่อง
- Port 27017 เปิดระหว่างเซิร์ฟเวอร์

## การกำหนดค่าเซิร์ฟเวอร์

- **เซิร์ฟเวอร์หลัก (Primary):** 127.0.0.1
- **เซิร์ฟเวอร์รอง 1:** 127.0.02
- **เซิร์ฟเวอร์รอง 2:** 127.0.03
- **ชื่อผู้ใช้ Admin:** admin
- **รหัสผ่าน Admin:** 123456

## ขั้นตอนการติดตั้ง

### ขั้นตอนที่ 1: รันสคริปต์การติดตั้งบนเซิร์ฟเวอร์ทุกเครื่อง

รันคำสั่งต่อไปนี้บน **เซิร์ฟเวอร์ทั้งสามเครื่อง** (หลักและรอง):

```bash
curl -fsSL https://raw.githubusercontent.com/vdohide/mongodb/refs/heads/main/replica.sh| sed 's/set -e/set +e/' | sudo -E bash -s 127.0.0.1,127.0.02,127.0.03 admin 123456
```

**คำสั่งนี้ทำอะไร:**

- ดาวน์โหลดสคริปต์การติดตั้ง MongoDB จาก GitHub
- แก้ไขสคริปต์ให้ดำเนินการต่อแม้เจอข้อผิดพลาด (`set +e` แทน `set -e`)
- รันสคริปต์ด้วย IP addresses และข้อมูลรับรองที่ระบุ
- กำหนดค่า MongoDB อัตโนมัติสำหรับการทำงานแบบ replica set

### ขั้นตอนที่ 2: รอให้การติดตั้งเสร็จสิ้น

สคริปต์การติดตั้งจะ:

- ✅ อัปเดตแพ็กเกจของระบบ
- ✅ เพิ่ม MongoDB 8.0 repository
- ✅ ติดตั้ง MongoDB พร้อมตรวจสอบ architecture (ARM64/x86_64)
- ✅ สร้าง replica set keyfile
- ✅ กำหนดค่า MongoDB สำหรับ replica set
- ✅ ปรับแต่งการตั้งค่าระบบ
- ✅ กำหนดค่า firewall rules
- ✅ เริ่มต้นบริการ MongoDB

### ขั้นตอนที่ 3: คัดลอก Keyfile (เซิร์ฟเวอร์หลักเท่านั้น)

หลังจากการติดตั้งเสร็จสิ้นบนเซิร์ฟเวอร์ทุกเครื่อง ให้รันคำสั่งเหล่านี้ **บนเซิร์ฟเวอร์หลักเท่านั้น** (127.0.0.1):

```bash
# คัดลอก keyfile ไปยังเซิร์ฟเวอร์รอง 1
scp /opt/mongodb/keyfile root@127.0.02:/opt/mongodb/keyfile

# คัดลอก keyfile ไปยังเซิร์ฟเวอร์รอง 2
scp /opt/mongodb/keyfile root@127.0.03:/opt/mongodb/keyfile
```

### ขั้นตอนที่ 4: ตั้งค่าสิทธิ์ Keyfile (เซิร์ฟเวอร์รองทั้งสอง)

รันคำสั่งเหล่านี้บน **เซิร์ฟเวอร์รองทั้งสองเครื่อง** (127.0.02 และ 127.0.03):

```bash
chmod 400 /opt/mongodb/keyfile
chown mongodb:mongodb /opt/mongodb/keyfile
systemctl restart mongod
```

### ขั้นตอนที่ 5: เริ่มต้น Replica Set (เซิร์ฟเวอร์หลักเท่านั้น)

รันคำสั่งนี้ **บนเซิร์ฟเวอร์หลักเท่านั้น** (127.0.0.1):

```bash
mongosh < /opt/mongodb/init-replica-set.js
```

### ขั้นตอนที่ 6: สร้างผู้ใช้ Admin (เซิร์ฟเวอร์หลักเท่านั้น)

รันคำสั่งนี้ **บนเซิร์ฟเวอร์หลักเท่านั้น** (127.0.0.1):

```bash
mongosh < /opt/mongodb/create-users.js
```

### ขั้นตอนที่ 7: ตรวจสอบการติดตั้ง

ตรวจสอบสถานะ replica set บนเซิร์ฟเวอร์ใดก็ได้:

```bash
/opt/mongodb/health-check.sh
```

หรือตรวจสอบแบบ manual:

```bash
mongosh --eval "rs.status()"
```

## Connection Strings

หลังจากติดตั้งสำเร็จแล้ว ให้ใช้ connection strings เหล่านี้:

### การเชื่อมต่อ Admin (สิทธิ์เต็ม)

```
mongodb://admin:123456@127.0.0.1:27017,127.0.02:27017,127.0.03:27017/admin?replicaSet=rs0&authSource=admin
```

### การเชื่อมต่อฐานข้อมูลแอปพลิเคชัน

```
mongodb://admin:123456@127.0.0.1:27017,127.0.02:27017,127.0.03:27017/DATABASE_NAME?replicaSet=rs0&authSource=admin
```

### พร้อม Read Preference (แนะนำ)

```
mongodb://admin:123456@127.0.0.1:27017,127.0.02:27017,127.0.03:27017/DATABASE_NAME?replicaSet=rs0&authSource=admin&readPreference=secondaryPreferred
```

## ตัวอย่างการเชื่อมต่อฐานข้อมูล

### ฐานข้อมูล VdoHide

```
mongodb://admin:123456@127.0.0.1:27017,127.0.02:27017,127.0.03:27017/vdohide?replicaSet=rs0&authSource=admin
```

### ฐานข้อมูล Test

```
mongodb://admin:123456@127.0.0.1:27017,127.0.02:27017,127.0.03:27017/test?replicaSet=rs0&authSource=admin
```

## การตั้งค่า Backup (ไม่บังคับ)

ตั้งค่าการสำรองข้อมูลอัตโนมัติรายวันโดยเพิ่มใน crontab:

```bash
crontab -e
```

เพิ่มบรรทัดนี้:

```
0 2 * * * /opt/mongodb/backup.sh
```

## การแก้ไขปัญหา

### ปัญหาที่พบบ่อย

1. **MongoDB service ไม่สามารถเริ่มต้นได้**

   ```bash
   systemctl status mongod
   journalctl -u mongod -f
   ```

2. **การเริ่มต้น Replica set ล้มเหลว**

   ```bash
   mongosh --eval "rs.status()"
   cat /var/log/mongodb/mongod.log
   ```

3. **ปัญหาการเชื่อมต่อ**
   - ตรวจสอบการตั้งค่า firewall: `ufw status`
   - ตรวจสอบว่า MongoDB กำลัง listening: `netstat -tlnp | grep 27017`
   - ทดสอบการเชื่อมต่อ: `telnet <server_ip> 27017`

### ไฟล์ Log

- MongoDB logs: `/var/log/mongodb/mongod.log`
- Installation logs: `/var/log/mongodb-install.log`
- Backup logs: `/var/log/mongodb-backup.log`

## คำแนะนำด้านความปลอดภัย

1. **เปลี่ยนรหัสผ่านเริ่มต้น**

   ```bash
   mongosh admin --eval "db.changeUserPassword('admin', 'NEW_SECURE_PASSWORD')"
   ```

2. **สร้างผู้ใช้เฉพาะสำหรับแอปพลิเคชัน**

   ```javascript
   use your_database
   db.createUser({
     user: "app_user",
     pwd: "secure_password",
     roles: [{ role: "readWrite", db: "your_database" }]
   })
   ```

3. **เปิดใช้งาน SSL/TLS** (แนะนำสำหรับ production)

4. **อัปเดตความปลอดภัยเป็นประจำ**
   ```bash
   apt update && apt upgrade
   ```

## การรองรับ Architecture

สคริปต์การติดตั้งนี้รองรับ:

- ✅ **x86_64 (AMD64)** - โปรเซสเซอร์ Intel/AMD
- ✅ **ARM64 (AArch64)** - โปรเซสเซอร์ ARM (Apple M1/M2, AWS Graviton, ฯลฯ)

สคริปต์จะตรวจสอบ architecture ของเซิร์ฟเวอร์โดยอัตโนมัติและใช้การปรับแต่งที่เหมาะสม

## หมายเหตุสุดท้าย

- ผู้ใช้ admin มี **สิทธิ์เต็มในการเข้าถึงฐานข้อมูลทั้งหมด**
- เซิร์ฟเวอร์ทุกเครื่องได้รับการกำหนดค่าที่ปรับแต่งสำหรับ MongoDB
- Transparent Huge Pages ถูกปิดการใช้งานเพื่อประสิทธิภาพที่ดีขึ้น
- Firewall ได้รับการกำหนดค่าเพื่อให้ replica set สื่อสารได้
- System limits ได้รับการปรับแต่งสำหรับการทำงานของ MongoDB

## การสนับสนุน

สำหรับปัญหาหรือคำถาม:

1. ตรวจสอบไฟล์ log ที่กล่าวข้างต้น
2. ดู MongoDB documentation: https://docs.mongodb.com/
3. ตรวจสอบสถานะ replica set ด้วย health check script

---

**วันที่ติดตั้ง:** $(date)  
**MongoDB Version:** 8.0  
**แหล่งที่มาของสคริปต์:** https://raw.githubusercontent.com/vdohide/mongodb/refs/heads/main/replica.sh
