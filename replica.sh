#!/bin/bash

# MongoDB Replica Set Installation Script
# Author: VdoHide Team
# Date: $(date)
# Description: Automated installation script for MongoDB 8.0 Replica Set
# Usage: ./install-mongodb-replica.sh ip1,ip2,ip3 username password

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
MONGODB_VERSION="8.0"
KEYFILE_PATH="/opt/mongodb/keyfile"
CONFIG_FILE="/etc/mongod.conf"
LOG_FILE="/var/log/mongodb-install.log"

# Detect CPU architecture
ARCH=$(uname -m)
case $ARCH in
    x86_64)
        MONGODB_ARCH="amd64"
        ;;
    aarch64|arm64)
        MONGODB_ARCH="arm64"
        ;;
    *)
        print_error "Unsupported architecture: $ARCH"
        echo "Supported architectures: x86_64 (amd64), aarch64/arm64"
        exit 1
        ;;
esac

# Command line arguments
IP_LIST="$1"
ADMIN_USERNAME="$2"
ADMIN_PASSWORD="$3"

# Replica Set Configuration - Will be set during script execution
declare -A REPLICA_NODES

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1" | tee -a $LOG_FILE
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a $LOG_FILE
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a $LOG_FILE
}

print_header() {
    echo -e "${BLUE}======================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}======================================${NC}"
}

# Function to check if script is run as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root. Use sudo."
        exit 1
    fi
}

# Function to show usage
show_usage() {
    echo ""
    echo -e "${BLUE}Usage:${NC}"
    echo "  $0 ip1,ip2,ip3 username password"
    echo ""
    echo -e "${BLUE}Examples:${NC}"
    echo "  $0 192.168.1.10,192.168.1.11,192.168.1.12 admin mypassword123"
    echo "  $0 1.2.3.4,1.2.3.5,1.2.3.6 vdohide_admin secretpass456"
    echo ""
    echo -e "${BLUE}Parameters:${NC}"
    echo "  ip1,ip2,ip3    - Comma-separated list of IP addresses (minimum 3)"
    echo "  username       - MongoDB admin username"
    echo "  password       - MongoDB admin password"
    echo ""
}

# Function to validate arguments
validate_arguments() {
    print_header "VALIDATING COMMAND LINE ARGUMENTS"
    
    # Check if all arguments are provided
    if [ -z "$IP_LIST" ] || [ -z "$ADMIN_USERNAME" ] || [ -z "$ADMIN_PASSWORD" ]; then
        print_error "Missing required arguments!"
        show_usage
        exit 1
    fi
    
    # Parse IP list
    IFS=',' read -ra IP_ARRAY <<< "$IP_LIST"
    
    # Check minimum IP count
    if [ ${#IP_ARRAY[@]} -lt 3 ]; then
        print_error "At least 3 IP addresses are required for a replica set!"
        show_usage
        exit 1
    fi
    
    # Validate each IP address
    local ip_count=0
    for ip in "${IP_ARRAY[@]}"; do
        ip=$(echo "$ip" | xargs)  # Trim whitespace
        if ! validate_ip "$ip"; then
            print_error "Invalid IP address: $ip"
            exit 1
        fi
        
        # Assign to replica nodes
        case $ip_count in
            0) REPLICA_NODES["primary"]=$ip ;;
            1) REPLICA_NODES["secondary1"]=$ip ;;
            2) REPLICA_NODES["secondary2"]=$ip ;;
            *) REPLICA_NODES["secondary$ip_count"]=$ip ;;
        esac
        
        ((ip_count++))
    done
    
    # Validate username
    if [[ ! "$ADMIN_USERNAME" =~ ^[a-zA-Z][a-zA-Z0-9_]{2,19}$ ]]; then
        print_error "Invalid username! Must start with letter, 3-20 chars, alphanumeric and underscore only."
        exit 1
    fi
    
    # Validate password
    if [ ${#ADMIN_PASSWORD} -lt 8 ]; then
        print_error "Password must be at least 8 characters long!"
        exit 1
    fi
    
    print_status "✅ Command line arguments validated successfully"
    print_status "IPs: $IP_LIST"
    print_status "Username: $ADMIN_USERNAME"
    print_status "Password: [HIDDEN]"
    print_status "Total servers: ${#IP_ARRAY[@]}"
}

# Function to get current server IP
get_current_ip() {
    # Try multiple methods to get the server's IP
    local ip=""
    
    # Method 1: Check default route
    ip=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K\S+' | head -n1)
    
    # Method 2: If method 1 fails, try hostname -I
    if [ -z "$ip" ]; then
        ip=$(hostname -I | awk '{print $1}')
    fi
    
    # Method 3: If still no IP, try ip addr
    if [ -z "$ip" ]; then
        ip=$(ip addr show | grep -oP 'inet \K[\d.]+' | grep -v '127.0.0.1' | head -n1)
    fi
    
    echo "$ip"
}

# Function to validate IP address
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -ra ADDR <<< "$ip"
        for i in "${ADDR[@]}"; do
            if [ "$i" -gt 255 ]; then
                return 1
            fi
        done
        return 0
    else
        return 1
    fi
}

# Function to configure replica set IPs
configure_replica_ips() {
    print_header "CONFIGURING REPLICA SET IP ADDRESSES"
    
    # If command line args provided, use them directly
    if [ -n "$IP_LIST" ]; then
        print_status "Using command line provided IP addresses"
        print_status "Replica Set Configuration:"
        for key in "${!REPLICA_NODES[@]}"; do
            print_status "$key: ${REPLICA_NODES[$key]}"
        done
        
        # Save configuration to file
        cat > /opt/mongodb/replica-config.conf << EOF
# MongoDB Replica Set Configuration
# Generated on $(date)
PRIMARY_IP=${REPLICA_NODES[primary]}
SECONDARY1_IP=${REPLICA_NODES[secondary1]}
SECONDARY2_IP=${REPLICA_NODES[secondary2]}
REPLICA_SET_NAME=rs0
ADMIN_USERNAME=$ADMIN_USERNAME
# Note: Password not stored in config file for security
EOF
        print_status "Configuration saved to /opt/mongodb/replica-config.conf"
        return
    fi
    
    # Check if configuration file exists
    if [ -f "/opt/mongodb/replica-config.conf" ]; then
        print_status "Found existing configuration file"
        source /opt/mongodb/replica-config.conf
        
        if [ -n "$PRIMARY_IP" ] && [ -n "$SECONDARY1_IP" ] && [ -n "$SECONDARY2_IP" ]; then
            REPLICA_NODES["primary"]=$PRIMARY_IP
            REPLICA_NODES["secondary1"]=$SECONDARY1_IP
            REPLICA_NODES["secondary2"]=$SECONDARY2_IP
            
            print_status "Loaded configuration:"
            print_status "Primary:     ${REPLICA_NODES[primary]}"
            print_status "Secondary 1: ${REPLICA_NODES[secondary1]}"  
            print_status "Secondary 2: ${REPLICA_NODES[secondary2]}"
            
            echo -n "Use existing configuration? (Y/n): "
            read use_existing
            if [[ ! $use_existing =~ ^[Nn]$ ]]; then
                print_status "Using existing IP configuration"
                return
            fi
        fi
    fi
    
    # Get current server IP
    CURRENT_IP=$(get_current_ip)
    print_status "Detected current server IP: $CURRENT_IP"
    
    echo ""
    echo -e "${YELLOW}Please configure your replica set IP addresses:${NC}"
    echo ""
    
    # Primary IP
    while true; do
        echo -n "Enter PRIMARY server IP [$CURRENT_IP]: "
        read primary_ip
        if [ -z "$primary_ip" ]; then
            primary_ip=$CURRENT_IP
        fi
        
        if validate_ip "$primary_ip"; then
            REPLICA_NODES["primary"]=$primary_ip
            break
        else
            print_error "Invalid IP address. Please try again."
        fi
    done
    
    # Secondary 1 IP
    while true; do
        echo -n "Enter SECONDARY 1 server IP: "
        read secondary1_ip
        if [ -z "$secondary1_ip" ]; then
            print_error "Secondary server IP cannot be empty"
            continue
        fi
        
        if validate_ip "$secondary1_ip"; then
            if [ "$secondary1_ip" == "${REPLICA_NODES[primary]}" ]; then
                print_error "Secondary IP cannot be the same as primary IP"
                continue
            fi
            REPLICA_NODES["secondary1"]=$secondary1_ip
            break
        else
            print_error "Invalid IP address. Please try again."
        fi
    done
    
    # Secondary 2 IP
    while true; do
        echo -n "Enter SECONDARY 2 server IP: "
        read secondary2_ip
        if [ -z "$secondary2_ip" ]; then
            print_error "Secondary server IP cannot be empty"
            continue
        fi
        
        if validate_ip "$secondary2_ip"; then
            if [ "$secondary2_ip" == "${REPLICA_NODES[primary]}" ] || [ "$secondary2_ip" == "${REPLICA_NODES[secondary1]}" ]; then
                print_error "Secondary IP must be unique"
                continue
            fi
            REPLICA_NODES["secondary2"]=$secondary2_ip
            break
        else
            print_error "Invalid IP address. Please try again."
        fi
    done
    
    # Confirm configuration
    echo ""
    print_status "Replica Set Configuration:"
    print_status "Primary:     ${REPLICA_NODES[primary]}"
    print_status "Secondary 1: ${REPLICA_NODES[secondary1]}"  
    print_status "Secondary 2: ${REPLICA_NODES[secondary2]}"
    echo ""
    
    echo -n "Is this configuration correct? (y/N): "
    read confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        print_error "Configuration cancelled. Please run the script again."
        exit 1
    fi
    
    print_status "IP configuration completed"
    
    # Save configuration to file for future reference
    cat > /opt/mongodb/replica-config.conf << EOF
# MongoDB Replica Set Configuration
# Generated on $(date)
PRIMARY_IP=${REPLICA_NODES[primary]}
SECONDARY1_IP=${REPLICA_NODES[secondary1]}
SECONDARY2_IP=${REPLICA_NODES[secondary2]}
REPLICA_SET_NAME=rs0
EOF
    
    print_status "Configuration saved to /opt/mongodb/replica-config.conf"
}

# Function to detect OS
detect_os() {
    print_status "Detecting operating system..."
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VERSION=$VERSION_ID
        print_status "Detected OS: $OS $VERSION"
    else
        print_error "Cannot detect operating system"
        exit 1
    fi
    
    # Check if Ubuntu 20.04 (focal)
    if [[ "$OS" == *"Ubuntu"* ]] && [[ "$VERSION" == "20.04" ]]; then
        UBUNTU_CODENAME="focal"
        print_status "Ubuntu 20.04 (focal) detected - supported"
    else
        print_warning "This script is optimized for Ubuntu 20.04. Proceeding anyway..."
        UBUNTU_CODENAME="focal"
    fi
}

# Function to update system
update_system() {
    print_header "UPDATING SYSTEM"
    
    print_status "Updating package list..."
    apt update >> $LOG_FILE 2>&1
    
    print_status "Installing required packages..."
    apt install -y wget gnupg curl software-properties-common >> $LOG_FILE 2>&1
    
    print_status "System update completed"
}

# Function to add MongoDB repository
add_mongodb_repo() {
    print_header "ADDING MONGODB REPOSITORY"
    
    print_status "Adding MongoDB GPG key..."
    curl -fsSL https://www.mongodb.org/static/pgp/server-${MONGODB_VERSION}.asc | \
        gpg --dearmor -o /usr/share/keyrings/mongodb-server-${MONGODB_VERSION}.gpg
    
    print_status "Adding MongoDB repository..."
    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-${MONGODB_VERSION}.gpg ] https://repo.mongodb.org/apt/ubuntu ${UBUNTU_CODENAME}/mongodb-org/${MONGODB_VERSION} multiverse" | \
        tee /etc/apt/sources.list.d/mongodb-org-${MONGODB_VERSION}.list
    
    print_status "Updating package list with MongoDB repository..."
    apt update >> $LOG_FILE 2>&1
    
    print_status "MongoDB repository added successfully"
}

# Function to install MongoDB
install_mongodb() {
    print_header "INSTALLING MONGODB"
    
    print_status "Detected architecture: $ARCH ($MONGODB_ARCH)"
    print_status "Installing MongoDB ${MONGODB_VERSION} for $MONGODB_ARCH architecture..."
    apt install -y mongodb-org >> $LOG_FILE 2>&1
    
    # Prevent automatic updates
    print_status "Holding MongoDB packages to prevent automatic updates..."
    echo "mongodb-org hold" | dpkg --set-selections
    echo "mongodb-org-database hold" | dpkg --set-selections
    echo "mongodb-org-server hold" | dpkg --set-selections
    echo "mongodb-mongosh hold" | dpkg --set-selections
    echo "mongodb-org-mongos hold" | dpkg --set-selections
    echo "mongodb-org-tools hold" | dpkg --set-selections
    
    # Configure ulimits for MongoDB
    print_status "Configuring system limits for MongoDB..."
    
    # Base limits for all architectures
    BASE_NOFILE=64000
    BASE_NPROC=64000
    
    # ARM64 typically has more cores, so increase limits
    if [[ "$MONGODB_ARCH" == "arm64" ]]; then
        print_status "Applying enhanced limits for ARM64 architecture..."
        BASE_NOFILE=96000
        BASE_NPROC=96000
    fi
    
    # Set limits in limits.conf
    cat >> /etc/security/limits.conf << EOF

# MongoDB limits - Added by install script
mongodb soft nofile $BASE_NOFILE
mongodb hard nofile $BASE_NOFILE
mongodb soft nproc $BASE_NPROC
mongodb hard nproc $BASE_NPROC
mongod soft nofile $BASE_NOFILE
mongod hard nofile $BASE_NOFILE
mongod soft nproc $BASE_NPROC
mongod hard nproc $BASE_NPROC
EOF
    
    print_status "MongoDB installation completed"
}

# Function to create keyfile
create_keyfile() {
    print_header "CREATING REPLICA SET KEYFILE"
    
    print_status "Creating MongoDB directory..."
    mkdir -p /opt/mongodb
    
    print_status "Generating keyfile..."
    openssl rand -base64 756 > $KEYFILE_PATH
    
    print_status "Setting keyfile permissions..."
    chmod 400 $KEYFILE_PATH
    chown mongodb:mongodb $KEYFILE_PATH
    
    print_status "Keyfile created successfully at $KEYFILE_PATH"
}

# Function to configure MongoDB
configure_mongodb() {
    print_header "CONFIGURING MONGODB"
    
    print_status "Creating MongoDB configuration file..."
    
    # Backup original config if exists
    if [ -f $CONFIG_FILE ]; then
        cp $CONFIG_FILE ${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)
        print_status "Original config backed up"
    fi
    
    # Create log directory
    mkdir -p /var/log/mongodb
    chown mongodb:mongodb /var/log/mongodb
    
    # Detect MongoDB version to use appropriate config format
    MONGODB_INSTALLED_VERSION=$(mongod --version 2>/dev/null | grep -oP 'db version v\K[0-9.]+' | head -n1)
    
    if [[ -z "$MONGODB_INSTALLED_VERSION" ]]; then
        print_warning "Cannot detect MongoDB version, using legacy config format"
        MONGODB_INSTALLED_VERSION="4.4"
    fi
    
    print_status "Detected MongoDB version: $MONGODB_INSTALLED_VERSION"
    
    # Use MongoDB 8.0.12 compatible YAML configuration
    print_status "Creating MongoDB 8.0.12 compatible YAML configuration"
    
    cat > $CONFIG_FILE << EOF
# MongoDB 8.0.12 Configuration (YAML Format - Production Ready)
# Generated by install script on $(date)

net:
  port: 27017
  bindIp: 0.0.0.0
  maxIncomingConnections: 1000

storage:
  dbPath: /var/lib/mongodb
  # Note: journal.enabled removed - always enabled in 8.0+
  wiredTiger:
    engineConfig:
      cacheSizeGB: 4
      journalCompressor: zstd
    collectionConfig:
      blockCompressor: zstd

systemLog:
  destination: file
  logAppend: true
  path: /var/log/mongodb/mongod.log
  verbosity: 0

replication:
  replSetName: rs0

security:
  authorization: enabled
  keyFile: $KEYFILE_PATH

processManagement:
  fork: true
  pidFilePath: /var/run/mongodb/mongod.pid

# MongoDB 8.0+ specific optimizations
setParameter:
  maxLogSizeKB: 100000
  logLevel: 1
EOF

    # Set proper permissions and create PID directory
    mkdir -p /var/run/mongodb
    chown mongodb:mongodb /var/run/mongodb
    chown mongodb:mongodb $CONFIG_FILE
    
    print_status "MongoDB 8.0.12 compatible configuration created"
}

# Function to optimize system
optimize_system() {
    print_header "OPTIMIZING SYSTEM FOR MONGODB"
    
    print_status "Setting kernel parameters for $MONGODB_ARCH architecture..."
    
    # Add kernel parameters to sysctl.conf
    cat >> /etc/sysctl.conf << EOF

# MongoDB Optimizations - Added by install script
vm.swappiness=1
vm.dirty_ratio=15
vm.dirty_background_ratio=5
vm.overcommit_memory=1
net.core.somaxconn=4096
net.ipv4.tcp_fin_timeout=30
net.ipv4.tcp_keepalive_intvl=30
net.ipv4.tcp_keepalive_time=120
net.ipv4.tcp_max_syn_backlog=4096
EOF

    # ARM-specific optimizations
    if [[ "$MONGODB_ARCH" == "arm64" ]]; then
        print_status "Applying ARM64-specific optimizations..."
        cat >> /etc/sysctl.conf << EOF

# ARM64-specific optimizations
net.core.netdev_max_backlog=5000
net.ipv4.tcp_rmem=4096 65536 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
EOF
    fi
    
    # Apply sysctl settings
    sysctl -p >> $LOG_FILE 2>&1
    
    # Configure Transparent Huge Pages based on architecture
    if [[ "$MONGODB_ARCH" == "arm64" ]]; then
        print_status "Configuring Transparent Huge Pages for ARM64..."
        # ARM64 can benefit from THP in some cases, but MongoDB prefers it disabled
        echo never > /sys/kernel/mm/transparent_hugepage/enabled
        echo never > /sys/kernel/mm/transparent_hugepage/defrag
        THP_SETTING="never"
    else
        print_status "Disabling transparent huge pages for x86_64..."
        echo never > /sys/kernel/mm/transparent_hugepage/enabled
        echo never > /sys/kernel/mm/transparent_hugepage/defrag
        THP_SETTING="never"
    fi
    
    # Make it persistent
    cat > /etc/systemd/system/disable-thp.service << 'EOF'
[Unit]
Description=Disable Transparent Huge Pages (THP)
DefaultDependencies=no
After=sysinit.target local-fs.target
Before=mongod.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/enabled && echo never > /sys/kernel/mm/transparent_hugepage/defrag'

[Install]
WantedBy=basic.target
EOF
    
    systemctl daemon-reload
    systemctl enable disable-thp
    systemctl start disable-thp
    
    print_status "System optimization completed"
}

# Function to configure firewall
configure_firewall() {
    print_header "CONFIGURING FIREWALL"
    
    print_status "Configuring UFW firewall for MongoDB..."
    
    # Enable UFW if not already enabled
    ufw --force enable >> $LOG_FILE 2>&1
    
    # Allow MongoDB port
    ufw allow 27017/tcp >> $LOG_FILE 2>&1
    
    # Allow replica set members
    for node in "${REPLICA_NODES[@]}"; do
        print_status "Allowing connection from $node"
        ufw allow from $node to any port 27017 >> $LOG_FILE 2>&1
    done
    
    # Allow SSH (important!)
    ufw allow ssh >> $LOG_FILE 2>&1
    
    print_status "Firewall configuration completed"
    ufw status
}

# Function to start MongoDB service
start_mongodb_service() {
    print_header "STARTING MONGODB SERVICE"
    
    print_status "Enabling MongoDB service..."
    systemctl daemon-reload
    systemctl enable mongod
    
    print_status "Starting MongoDB service..."
    systemctl start mongod
    
    # Wait for MongoDB to start
    print_status "Waiting for MongoDB to start..."
    sleep 10
    
    # Check service status
    if systemctl is-active --quiet mongod; then
        print_status "MongoDB service is running"
        systemctl status mongod --no-pager
    else
        print_error "MongoDB service failed to start"
        systemctl status mongod --no-pager
        exit 1
    fi
}

# Function to show keyfile for copying
show_keyfile_info() {
    print_header "KEYFILE DISTRIBUTION"
    
    print_status "Keyfile created at: $KEYFILE_PATH"
    print_warning "IMPORTANT: Copy this keyfile to other replica set members!"
    
    echo ""
    echo "Execute these commands on the PRIMARY node to copy keyfile to secondary nodes:"
    echo ""
    for key in "${!REPLICA_NODES[@]}"; do
        if [ "$key" != "primary" ]; then
            node_ip="${REPLICA_NODES[$key]}"
            echo -e "${YELLOW}scp $KEYFILE_PATH root@${node_ip}:$KEYFILE_PATH${NC}"
        fi
    done
    echo ""
    
    print_warning "Make sure to set proper permissions on secondary nodes:"
    echo -e "${YELLOW}chmod 400 $KEYFILE_PATH${NC}"
    echo -e "${YELLOW}chown mongodb:mongodb $KEYFILE_PATH${NC}"
}

# Function to create replica set initialization script
create_replica_init_script() {
    print_header "CREATING REPLICA SET INITIALIZATION SCRIPT"
    
    cat > /opt/mongodb/init-replica-set.js << EOF
// MongoDB Replica Set Initialization Script
// Run this script on the PRIMARY node only after all nodes are configured

// Initialize replica set
var config = {
  _id: "rs0",
  members: [
EOF

    # Generate members array dynamically
    local member_id=0
    for key in "${!REPLICA_NODES[@]}"; do
        local priority=1
        if [[ "$key" == "primary" ]]; then
            priority=2
        fi
        
        cat >> /opt/mongodb/init-replica-set.js << EOF
    { _id: $member_id, host: "${REPLICA_NODES[$key]}:27017", priority: $priority },
EOF
        ((member_id++))
    done
    
    # Remove last comma and close the configuration
    sed -i '$ s/,$//' /opt/mongodb/init-replica-set.js
    
    cat >> /opt/mongodb/init-replica-set.js << EOF
  ]
};

rs.initiate(config);

// Wait for replica set to be ready
print("Waiting for replica set initialization...");
sleep(5000);

// Check status
rs.status();
EOF
    
    cat > /opt/mongodb/create-users.js << EOF
// MongoDB User Creation Script
// Run this script on the PRIMARY node after replica set is initialized

// Create admin user with full access to all databases
use admin
db.createUser({
  user: "$ADMIN_USERNAME",
  pwd: "$ADMIN_PASSWORD",
  roles: [
    { role: "root", db: "admin" },
    { role: "readWriteAnyDatabase", db: "admin" },
    { role: "dbAdminAnyDatabase", db: "admin" },
    { role: "userAdminAnyDatabase", db: "admin" }
  ]
});

print("Admin user '$ADMIN_USERNAME' created successfully with full access to all databases!");
print("");
print("=== CONNECTION STRINGS ===");
print("");
EOF

    # Generate connection strings dynamically
    local all_hosts=""
    for key in "${!REPLICA_NODES[@]}"; do
        if [ -z "$all_hosts" ]; then
            all_hosts="${REPLICA_NODES[$key]}:27017"
        else
            all_hosts="${all_hosts},${REPLICA_NODES[$key]}:27017"
        fi
    done
    
    cat >> /opt/mongodb/create-users.js << EOF
print("Standard Connection:");
print("mongodb://$ADMIN_USERNAME:$ADMIN_PASSWORD@$all_hosts/DATABASE_NAME?replicaSet=rs0&authSource=admin");
print("");
print("With Read Preference:");
print("mongodb://$ADMIN_USERNAME:$ADMIN_PASSWORD@$all_hosts/DATABASE_NAME?replicaSet=rs0&authSource=admin&readPreference=secondaryPreferred");
print("");
print("Examples:");
print("mongodb://$ADMIN_USERNAME:$ADMIN_PASSWORD@$all_hosts/vdohide?replicaSet=rs0&authSource=admin");
print("mongodb://$ADMIN_USERNAME:$ADMIN_PASSWORD@$all_hosts/test?replicaSet=rs0&authSource=admin");
EOF
    
    print_status "Replica set initialization scripts created in /opt/mongodb/"
}

# Function to create backup script
create_backup_script() {
    print_header "CREATING BACKUP SCRIPT"
    
    cat > /opt/mongodb/backup.sh << EOF
#!/bin/bash

# MongoDB Backup Script
DATE=\$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/opt/mongodb/backups"
LOG_FILE="/var/log/mongodb-backup.log"

# Create backup directory
mkdir -p \$BACKUP_DIR

echo "\$(date): Starting MongoDB backup..." >> \$LOG_FILE

# Build connection string dynamically
CONNECTION_STRING="rs0/"
EOF

    # Add all hosts to connection string
    for key in "${!REPLICA_NODES[@]}"; do
        cat >> /opt/mongodb/backup.sh << EOF
CONNECTION_STRING="\$CONNECTION_STRING${REPLICA_NODES[$key]}:27017,"
EOF
    done
    
    cat >> /opt/mongodb/backup.sh << EOF
# Remove trailing comma
CONNECTION_STRING=\${CONNECTION_STRING%,}

# Backup using mongodump
mongodump --host "\$CONNECTION_STRING" \\
  --username $ADMIN_USERNAME \\
  --password $ADMIN_PASSWORD \\
  --authenticationDatabase admin \\
  --out \$BACKUP_DIR/backup_\$DATE >> \$LOG_FILE 2>&1

if [ \$? -eq 0 ]; then
    echo "\$(date): Backup completed successfully" >> \$LOG_FILE
    
    # Compress backup
    tar -czf \$BACKUP_DIR/backup_\$DATE.tar.gz \$BACKUP_DIR/backup_\$DATE
    rm -rf \$BACKUP_DIR/backup_\$DATE
    
    # Remove backups older than 7 days
    find \$BACKUP_DIR -name "backup_*.tar.gz" -mtime +7 -delete
    
    echo "\$(date): Backup compressed and old backups cleaned" >> \$LOG_FILE
else
    echo "\$(date): Backup failed!" >> \$LOG_FILE
    exit 1
fi
EOF
    
    chmod +x /opt/mongodb/backup.sh
    print_status "Backup script created at /opt/mongodb/backup.sh"
}

# Function to create health check script
create_health_check_script() {
    print_header "CREATING HEALTH CHECK SCRIPT"
    
    cat > /opt/mongodb/health-check.sh << 'EOF'
#!/bin/bash

# MongoDB Health Check Script
echo "=== MongoDB Health Check ==="
echo "Date: $(date)"
echo ""

# Check if MongoDB service is running
if systemctl is-active --quiet mongod; then
    echo "✅ MongoDB service is running"
else
    echo "❌ MongoDB service is not running"
    exit 1
fi

# Check MongoDB connectivity
if mongosh --quiet --eval "db.runCommand('ping')" > /dev/null 2>&1; then
    echo "✅ MongoDB is responding to connections"
else
    echo "❌ MongoDB is not responding"
    exit 1
fi

# Check replica set status
echo ""
echo "📊 Replica Set Status:"
mongosh --quiet --eval "
try {
    var status = rs.status();
    print('Replica Set: ' + status.set);
    print('Status: OK');
    status.members.forEach(function(member) {
        print('  ' + member.name + ': ' + member.stateStr);
    });
} catch(e) {
    print('❌ Replica Set Error: ' + e);
    quit(1);
}
"

echo ""
echo "💾 Disk Usage:"
df -h /var/lib/mongodb | tail -n 1

echo ""
echo "🔗 Connection Count:"
mongosh --quiet --eval "db.serverStatus().connections"

echo ""
echo "=== Health Check Complete ==="
EOF
    
    chmod +x /opt/mongodb/health-check.sh
    print_status "Health check script created at /opt/mongodb/health-check.sh"
}

# Function to show next steps
show_next_steps() {
    print_header "INSTALLATION COMPLETED!"
    
    print_status "MongoDB ${MONGODB_VERSION} has been installed and configured"
    
    echo ""
    echo -e "${GREEN}📋 NEXT STEPS:${NC}"
    echo ""
    echo "1. 🔑 Copy keyfile to other nodes:"
    for key in "${!REPLICA_NODES[@]}"; do
        if [ "$key" != "primary" ]; then
            node_ip="${REPLICA_NODES[$key]}"
            echo "   scp $KEYFILE_PATH root@${node_ip}:$KEYFILE_PATH"
        fi
    done
    echo ""
    
    echo "2. 🏃 Run this script on ALL replica set members"
    echo ""
    
    echo "3. 🔧 Initialize replica set (PRIMARY node only):"
    echo "   mongosh < /opt/mongodb/init-replica-set.js"
    echo ""
    
    echo "4. 👤 Create admin user (PRIMARY node only):"
    echo "   mongosh < /opt/mongodb/create-users.js"
    echo ""
    
    echo "5. 🔍 Check replica set status:"
    echo "   /opt/mongodb/health-check.sh"
    echo ""
    
    echo "6. 📁 Setup automated backups:"
    echo "   crontab -e"
    echo "   Add: 0 2 * * * /opt/mongodb/backup.sh"
    echo ""
    
    print_warning "Remember to:"
    echo "- Change admin password if using default"
    echo "- Configure monitoring"
    echo "- Test backup and restore procedures"
    echo "- Review security settings"
    echo "- Admin user '$ADMIN_USERNAME' has full access to all databases"
    echo ""
    
    echo -e "${BLUE}🔗 Connection Strings:${NC}"
    echo ""
    
    # Generate connection strings dynamically
    local all_hosts=""
    for key in "${!REPLICA_NODES[@]}"; do
        if [ -z "$all_hosts" ]; then
            all_hosts="${REPLICA_NODES[$key]}:27017"
        else
            all_hosts="${all_hosts},${REPLICA_NODES[$key]}:27017"
        fi
    done
    
    echo "Admin (Full Access - All Databases):"
    echo "mongodb://$ADMIN_USERNAME:$ADMIN_PASSWORD@$all_hosts/admin?replicaSet=rs0&authSource=admin"
    echo ""
    echo "Connect to Any Database:"
    echo "mongodb://$ADMIN_USERNAME:$ADMIN_PASSWORD@$all_hosts/DATABASE_NAME?replicaSet=rs0&authSource=admin"
    echo ""
    echo "Examples:"
    echo "mongodb://$ADMIN_USERNAME:$ADMIN_PASSWORD@$all_hosts/vdohide?replicaSet=rs0&authSource=admin"
    echo "mongodb://$ADMIN_USERNAME:$ADMIN_PASSWORD@$all_hosts/test?replicaSet=rs0&authSource=admin"
    echo ""
    echo "With Read Preference (Recommended):"
    echo "mongodb://$ADMIN_USERNAME:$ADMIN_PASSWORD@$all_hosts/vdohide?replicaSet=rs0&authSource=admin&readPreference=secondaryPreferred"
    echo ""
    
    print_status "Log file: $LOG_FILE"
}

# Main installation function
main() {
    print_header "MONGODB REPLICA SET INSTALLATION"
    
    # Validate command line arguments first
    validate_arguments
    
    print_status "Starting installation process..."
    
    # Create log file
    touch $LOG_FILE
    chmod 644 $LOG_FILE
    
    # Run installation steps
    check_root
    configure_replica_ips
    detect_os
    update_system
    add_mongodb_repo
    install_mongodb
    create_keyfile
    configure_mongodb
    optimize_system
    configure_firewall
    start_mongodb_service
    show_keyfile_info
    create_replica_init_script
    create_backup_script
    create_health_check_script
    show_next_steps
    
    print_status "Installation completed successfully!"
}

# Run main function
main "$@"
