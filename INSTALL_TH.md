# คู่มือติดตั้ง Podman Runtime สำหรับผู้ใช้ทั่วไป

**ระบบที่รองรับ:** Debian 13, Ubuntu 24.04 LTS และ Ubuntu 26.04 LTS แบบ 64-bit (amd64/x86_64)

**Ubuntu 26.04:** แพ็กเกจติดตั้ง `nftables` เป็น dependency และสร้างไฟล์ตั้งค่าใน `/etc/containers/containers.conf.d/` เพื่อให้ Netavark ใช้ `nftables` แทน `iptables` โดยไม่แก้ไฟล์ `/etc/containers/containers.conf` เดิม หากมีการตั้งค่าของผู้ดูแลหรือผู้ใช้ที่มีลำดับความสำคัญสูงกว่าต้องตรวจสอบ และวางแผน maintenance window ก่อนเปลี่ยนค่าเมื่อมี workload ทำงานอยู่

**เวอร์ชันเป้าหมาย:** Podman 6.1.4 / แพ็กเกจ 6.1.4-3 / Netavark และ Aardvark DNS 2.1.0 / crun 1.30.1 (อยู่ในแพ็กเกจ)

> **สำคัญ:** แพ็กเกจ 6.1.4-3 สำหรับทั้งสามระบบจะพร้อมใช้เมื่อ GitHub Actions ผ่านและเผยแพร่ Release แล้วเท่านั้น ถ้า Release ยังไม่ออก ตัวติดตั้งจะหยุด ไม่ดาวน์โหลดแพ็กเกจเก่าหรือฝืนติดตั้งข้ามระบบ

## ขั้นที่ 1 — ตรวจว่าเครื่องรองรับหรือไม่

เปิด Terminal หรือ SSH แล้วพิมพ์:

```bash
cat /etc/os-release
dpkg --print-architecture
```

ต้องเป็น Debian `13` หรือ Ubuntu `24.04` / `26.04` และ architecture `amd64`

เครื่องที่ใช้ Debian 12, Ubuntu 22.04, ARM64 หรือ OS อื่น **ยังไม่รองรับ** อย่านำไฟล์ .deb ข้ามระบบมาใช้

## ขั้นที่ 2 — เตรียมโปรแกรมดาวน์โหลด

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl python3
```

## ขั้นที่ 3 — ดาวน์โหลดตัวติดตั้ง

```bash
curl -fsSL https://raw.githubusercontent.com/speccycy/podman-runtime/main/scripts/install.sh -o podman-install.sh
```

คำสั่งนี้ดาวน์โหลด **สคริปต์ติดตั้ง** ไว้ในโฟลเดอร์ปัจจุบัน ยังไม่ได้ติดตั้ง Podman

สามารถเปิดดูไฟล์ก่อนใช้งานด้วย `less podman-install.sh`

## ขั้นที่ 4 — ติดตั้ง

```bash
sudo bash podman-install.sh
```

ตัวติดตั้งจะจัดการเองตามลำดับ:

1. ตรวจ Debian/Ubuntu และเลือกแพ็กเกจให้ตรงกับ OS
2. ดาวน์โหลดไฟล์ .deb จาก GitHub Release ที่ระบุเวอร์ชันไว้
3. ตรวจ SHA256 ทั้งแพ็กเกจและไฟล์รายการ SHA256SUMS
4. ตรวจคำสั่ง APT แบบจำลองก่อนลงจริง ถ้า APT จะถอนแพ็กเกจอื่นที่ไม่เกี่ยวข้องจะหยุด
5. ติดตั้งด้วย APT และตรวจเวอร์ชัน, cgroup v2, Netavark รวมถึง crun 1.30.1 ที่อยู่ในแพ็กเกจ โดยไม่เปลี่ยน crun ของระบบ
6. ตรวจว่า Docker, containerd, cloudflared และ AMP ที่เคยทำงานยังทำงานอยู่

**ไม่จำเป็นต้อง Build Podman หรือเลือก .deb เอง** และไม่จำเป็นต้องเปิด Podman service/socket สำหรับการใช้งานทั่วไป

อยากดูสิ่งที่จะทำโดยยังไม่ติดตั้ง:

```bash
sudo bash podman-install.sh --dry-run
```

## ขั้นที่ 5 — ตรวจสอบหลังติดตั้ง

```bash
podman --version
dpkg-query -W podman-runtime
podman info --format 'Cgroup={{.Host.CgroupsVersion}} Network={{.Host.NetworkBackend}}'
/usr/libexec/podman/crun --version
sudo podman info --format '{{.Host.OCIRuntime.Path}}'
sudo podman run --rm docker.io/library/alpine:3.21 echo PODMAN_OK
```

ผลที่คาดหวัง:

```text
podman version 6.1.4
podman-runtime 6.1.4-3
Cgroup=v2 Network=netavark
crun version 1.30.1
/usr/libexec/podman/crun
PODMAN_OK
```

ถ้าคำสั่งใดมี Error ให้หยุดตรวจ ไม่ข้ามขั้นไปใช้งาน Production

## ถ้าติดตั้ง Podman อยู่ก่อนแล้ว

**เครื่องที่มี Podman ใช้งานอยู่ต้องสำรองข้อมูลและวางแผน Maintenance ก่อนอัปเกรด** ตรวจข้อมูลก่อน:

```bash
podman ps -a
podman images
podman volume ls
```

ตรวจ Rootless containers (ในบัญชีผู้ใช้แต่ละคน) และ Quadlet/systemd ด้วย เพราะการตรวจของตัวติดตั้งมองเห็นเฉพาะ Podman ที่รันด้วยสิทธิ์ root เท่านั้น

- ถ้ามี Container กำลังรัน ตัวติดตั้งจะหยุด เพื่อป้องกันการเปลี่ยน runtime ระหว่างใช้งาน
- ถ้าเครื่องติดตั้ง Podman จาก APT ของ Ubuntu/Debian อยู่ก่อน ตัวติดตั้งจะไม่ลบของเก่าให้อัตโนมัติ ต้องตรวจข้อมูลและย้ายอย่างระมัดระวัง
- ถ้ามีไฟล์ Podman ที่ Build เองเก่าค้างอยู่ เช่น `/usr/local/bin/podman` ตัวติดตั้งจะหยุด
- ถ้า APT แจ้งว่าจะถอน Docker หรือแพ็กเกจอื่นที่ไม่เกี่ยวข้อง ตัวติดตั้งจะหยุด **ห้ามใช้ force เพื่อให้ผ่าน**

หลังเสร็จให้ตรวจบริการ Docker/AMP/Cloudflare และแอปพลิเคชันที่ใช้งานจริงด้วย

## ปัญหาที่เจอบ่อย

**ขึ้น Unsupported OS:** ใช้ OS/Architecture ไม่ตรงกับที่รองรับ

**ขึ้น Release not found:** แพ็กเกจเวอร์ชันใหม่ยังไม่เผยแพร่ ตรวจ https://github.com/speccycy/podman-runtime/releases

**Ubuntu แจ้งหา conmon/crun ไม่เจอ:** ตรวจว่ามี Ubuntu `universe` repository แล้วทำ `sudo apt-get update`

**ขึ้น Podman containers are running:** หยุดงานที่เกี่ยวข้องอย่างปลอดภัยก่อน อย่าลบ Container หรือ Volume เพียงเพื่อให้ Installer ผ่าน

**ติดตั้งสำเร็จแล้ว แต่ Container เริ่มไม่ได้:** ตรวจ `podman info`, kernel/cgroup, Firewall และ Netavark; ห้ามสรุปจากแค่ `podman --version`

## หมายเหตุสำหรับ INFH-WEB

คู่มือนี้รับรอง **แพ็กเกจ Podman Runtime** ไม่ได้แปลว่า INFH-WEB application, PostgreSQL, AMP และทุก integration ผ่านการทดสอบบน Ubuntu 24.04 แล้ว โปรดใช้คู่มือ Deployment ของ INFH-WEB ที่ระบุ OS รองรับแยกกัน

แหล่งข้อมูล: https://github.com/speccycy/podman-runtime
