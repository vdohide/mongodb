#!/bin/bash

# MongoDB SSL Certificate Creation Script
# Author: VdoHide Team
# Date: $(date)
# Description: Creates SSL certificates for MongoDB replica set with SAN (Subject Alternative Names)
# Usage: ./create-ssl-certs.sh

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SSL_DIR="/opt/mongodb/ssl"
CERT_VALIDITY_DAYS=365
COUNTRY="TH"
STATE="Bangkok"
CITY="Bangkok"
ORGANIZATION="VdoHide Ltd"
ORG_UNIT="Database Team"

# Domain and IP configurations
DOMAINS="$1"
IP_ADDRESSES="$2"
LOG_FILE="/var/log/mongodb-ssl-setup.log"

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

# Function to validate dependencies
check_dependencies() {
    print_header "CHECKING DEPENDENCIES"
    
    # Check if openssl is installed
    if ! command -v openssl &> /dev/null; then
        print_status "Installing OpenSSL..."
        apt update && apt install -y openssl
    else
        print_status "✅ OpenSSL is installed"
    fi
    
    # Check OpenSSL version
    OPENSSL_VERSION=$(openssl version)
    print_status "OpenSSL version: $OPENSSL_VERSION"
}

# Function to create SSL directory
create_ssl_directory() {
    print_header "CREATING SSL DIRECTORY"
    
    # Create SSL directory
    mkdir -p $SSL_DIR
    print_status "SSL directory created: $SSL_DIR"
    
    # Backup existing certificates if they exist
    if [ -f "$SSL_DIR/mongodb.pem" ]; then
        BACKUP_DIR="$SSL_DIR/backup_$(date +%Y%m%d_%H%M%S)"
        mkdir -p $BACKUP_DIR
        cp $SSL_DIR/*.* $BACKUP_DIR/ 2>/dev/null || true
        print_warning "Existing certificates backed up to: $BACKUP_DIR"
    fi
}

# Function to create OpenSSL configuration file
create_openssl_config() {
    print_header "CREATING OPENSSL CONFIGURATION"
    
    cat > $SSL_DIR/mongodb.conf << EOF
[req]
default_bits = 4096
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = $COUNTRY
ST = $STATE
L = $CITY
O = $ORGANIZATION
OU = $ORG_UNIT
CN = *.vdohide.dev

[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
EOF

    # Add DNS names
    local dns_count=1
    IFS=',' read -ra DNS_ARRAY <<< "$DOMAINS"
    for domain in "${DNS_ARRAY[@]}"; do
        domain=$(echo "$domain" | xargs)  # Trim whitespace
        echo "DNS.$dns_count = $domain" >> $SSL_DIR/mongodb.conf
        ((dns_count++))
    done
    
    # Add IP addresses
    local ip_count=1
    IFS=',' read -ra IP_ARRAY <<< "$IP_ADDRESSES"
    for ip in "${IP_ARRAY[@]}"; do
        ip=$(echo "$ip" | xargs)  # Trim whitespace
        echo "IP.$ip_count = $ip" >> $SSL_DIR/mongodb.conf
        ((ip_count++))
    done
    
    print_status "OpenSSL configuration created: $SSL_DIR/mongodb.conf"
    print_status "✅ Domains: $DOMAINS"
    print_status "✅ IP Addresses: $IP_ADDRESSES"
}

# Function to generate private key
generate_private_key() {
    print_header "GENERATING PRIVATE KEY"
    
    # Generate 4096-bit RSA private key
    openssl genrsa -out $SSL_DIR/mongodb.key 4096
    
    print_status "✅ Private key generated: $SSL_DIR/mongodb.key"
    
    # Set proper permissions
    chmod 600 $SSL_DIR/mongodb.key
    print_status "✅ Private key permissions set to 600"
}

# Function to generate certificate signing request
generate_csr() {
    print_header "GENERATING CERTIFICATE SIGNING REQUEST"
    
    # Generate CSR using the configuration file
    openssl req -new -key $SSL_DIR/mongodb.key -out $SSL_DIR/mongodb.csr -config $SSL_DIR/mongodb.conf
    
    print_status "✅ Certificate Signing Request generated: $SSL_DIR/mongodb.csr"
}

# Function to generate self-signed certificate
generate_certificate() {
    print_header "GENERATING SELF-SIGNED CERTIFICATE"
    
    # Generate self-signed certificate
    openssl x509 -req -in $SSL_DIR/mongodb.csr \
        -signkey $SSL_DIR/mongodb.key \
        -out $SSL_DIR/mongodb.crt \
        -days $CERT_VALIDITY_DAYS \
        -extensions v3_req \
        -extfile $SSL_DIR/mongodb.conf
    
    print_status "✅ Self-signed certificate generated: $SSL_DIR/mongodb.crt"
    print_status "✅ Certificate validity: $CERT_VALIDITY_DAYS days"
}

# Function to create combined PEM file
create_pem_file() {
    print_header "CREATING COMBINED PEM FILE"
    
    # Combine certificate and private key into PEM file
    cat $SSL_DIR/mongodb.crt $SSL_DIR/mongodb.key > $SSL_DIR/mongodb.pem
    
    print_status "✅ Combined PEM file created: $SSL_DIR/mongodb.pem"
    
    # Set proper permissions
    chmod 600 $SSL_DIR/mongodb.pem
    print_status "✅ PEM file permissions set to 600"
}

# Function to create CA certificate (for client verification)
create_ca_certificate() {
    print_header "CREATING CA CERTIFICATE"
    
    # Create CA private key
    openssl genrsa -out $SSL_DIR/ca.key 4096
    
    # Create CA certificate
    openssl req -new -x509 -days $CERT_VALIDITY_DAYS -key $SSL_DIR/ca.key -out $SSL_DIR/ca.crt \
        -subj "/C=$COUNTRY/ST=$STATE/L=$CITY/O=$ORGANIZATION/OU=Certificate Authority/CN=VdoHide MongoDB CA"
    
    # Create CA bundle
    cp $SSL_DIR/ca.crt $SSL_DIR/ca-bundle.crt
    
    print_status "✅ CA certificate created: $SSL_DIR/ca.crt"
    
    # Set permissions
    chmod 600 $SSL_DIR/ca.key
    chmod 644 $SSL_DIR/ca.crt
    chmod 644 $SSL_DIR/ca-bundle.crt
}

# Function to set ownership and permissions
set_permissions() {
    print_header "SETTING PERMISSIONS AND OWNERSHIP"
    
    # Set ownership to mongodb user
    chown -R mongodb:mongodb $SSL_DIR
    
    # Set file permissions
    chmod 700 $SSL_DIR
    chmod 600 $SSL_DIR/*.key
    chmod 600 $SSL_DIR/*.pem
    chmod 644 $SSL_DIR/*.crt
    chmod 644 $SSL_DIR/*.conf
    chmod 644 $SSL_DIR/*.csr
    
    print_status "✅ Ownership set to mongodb:mongodb"
    print_status "✅ File permissions configured securely"
}

# Function to verify certificates
verify_certificates() {
    print_header "VERIFYING CERTIFICATES"
    
    print_status "Certificate information:"
    openssl x509 -in $SSL_DIR/mongodb.crt -text -noout | grep -E "(Subject:|DNS:|IP Address:)"
    
    print_status "Certificate validity:"
    openssl x509 -in $SSL_DIR/mongodb.crt -noout -dates
    
    print_status "Testing certificate and key match:"
    CERT_HASH=$(openssl x509 -noout -modulus -in $SSL_DIR/mongodb.crt | openssl md5)
    KEY_HASH=$(openssl rsa -noout -modulus -in $SSL_DIR/mongodb.key | openssl md5)
    
    if [ "$CERT_HASH" = "$KEY_HASH" ]; then
        print_status "✅ Certificate and private key match"
    else
        print_error "❌ Certificate and private key do not match"
        exit 1
    fi
}

# Function to create MongoDB SSL configuration
create_mongodb_ssl_config() {
    print_header "CREATING MONGODB SSL CONFIGURATION"
    
    cat > $SSL_DIR/mongod-ssl.conf << EOF
# MongoDB SSL/TLS Configuration
# Add these settings to your /etc/mongod.conf

net:
  port: 27017
  bindIp: 0.0.0.0
  maxIncomingConnections: 1000
  tls:
    mode: requireTLS
    certificateKeyFile: $SSL_DIR/mongodb.pem
    CAFile: $SSL_DIR/ca-bundle.crt
    allowConnectionsWithoutCertificates: true
    allowInvalidHostnames: true

storage:
  dbPath: /var/lib/mongodb
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
  keyFile: /opt/mongodb/keyfile

processManagement:
  fork: true
  pidFilePath: /var/run/mongodb/mongod.pid

setParameter:
  maxLogSizeKB: 100000
  logLevel: 1
EOF
    
    print_status "✅ MongoDB SSL configuration created: $SSL_DIR/mongod-ssl.conf"
}

# Function to create distribution script
create_distribution_script() {
    print_header "CREATING CERTIFICATE DISTRIBUTION SCRIPT"
    
    cat > $SSL_DIR/distribute-certs.sh << 'EOF'
#!/bin/bash

# Certificate Distribution Script
SSL_DIR="/opt/mongodb/ssl"
SERVERS=("91.99.163.168" "91.99.209.211" "46.62.169.124")

echo "Distributing SSL certificates to replica set members..."

for server in "${SERVERS[@]}"; do
    echo "Copying certificates to $server..."
    
    # Create SSL directory on remote server
    ssh root@$server "mkdir -p $SSL_DIR"
    
    # Copy certificate files
    scp $SSL_DIR/mongodb.pem root@$server:$SSL_DIR/
    scp $SSL_DIR/mongodb.crt root@$server:$SSL_DIR/
    scp $SSL_DIR/mongodb.key root@$server:$SSL_DIR/
    scp $SSL_DIR/ca.crt root@$server:$SSL_DIR/
    scp $SSL_DIR/ca-bundle.crt root@$server:$SSL_DIR/
    scp $SSL_DIR/mongod-ssl.conf root@$server:$SSL_DIR/
    
    # Set permissions on remote server
    ssh root@$server "chown -R mongodb:mongodb $SSL_DIR && chmod 700 $SSL_DIR && chmod 600 $SSL_DIR/*.key && chmod 600 $SSL_DIR/*.pem && chmod 644 $SSL_DIR/*.crt"
    
    echo "✅ Certificates distributed to $server"
done

echo "Certificate distribution completed!"
echo ""
echo "Next steps:"
echo "1. Update /etc/mongod.conf on each server with SSL configuration"
echo "2. Restart MongoDB on each server: sudo systemctl restart mongod"
echo "3. Test SSL connection: mongosh 'mongodb://username:password@database.vdohide.dev:27017/dbname?replicaSet=rs0&authSource=admin&tls=true'"
EOF
    
    chmod +x $SSL_DIR/distribute-certs.sh
    print_status "✅ Distribution script created: $SSL_DIR/distribute-certs.sh"
}

# Function to create connection test script
create_connection_test() {
    print_header "CREATING CONNECTION TEST SCRIPT"
    
    cat > $SSL_DIR/test-ssl-connection.sh << 'EOF'
#!/bin/bash

# SSL Connection Test Script
echo "=== MongoDB SSL Connection Test ==="

# Test local connection
echo "Testing local SSL connection..."
mongosh --tls --tlsCertificateKeyFile /opt/mongodb/ssl/mongodb.pem --tlsCAFile /opt/mongodb/ssl/ca-bundle.crt --host localhost:27017 --eval "db.runCommand('ping')"

# Test replica set connection
echo ""
echo "Testing replica set SSL connection..."
mongosh "mongodb://localhost:27017,91.99.209.211:27017,46.62.169.124:27017/?replicaSet=rs0&tls=true&tlsInsecure=true" --eval "rs.status()"

# Test domain connection
echo ""
echo "Testing domain SSL connection..."
mongosh "mongodb://database.vdohide.dev:27017/?tls=true&tlsInsecure=true" --eval "db.runCommand('ping')"

echo ""
echo "=== SSL Connection Test Complete ==="
EOF
    
    chmod +x $SSL_DIR/test-ssl-connection.sh
    print_status "✅ Connection test script created: $SSL_DIR/test-ssl-connection.sh"
}

# Function to show completion summary
show_completion_summary() {
    print_header "SSL CERTIFICATE SETUP COMPLETED!"
    
    print_status "✅ SSL certificates created successfully"
    
    echo ""
    echo -e "${GREEN}📁 Generated Files:${NC}"
    echo "   🔑 Private Key:     $SSL_DIR/mongodb.key"
    echo "   📜 Certificate:     $SSL_DIR/mongodb.crt"
    echo "   📦 Combined PEM:    $SSL_DIR/mongodb.pem"
    echo "   🏛️  CA Certificate:  $SSL_DIR/ca.crt"
    echo "   📋 SSL Config:      $SSL_DIR/mongod-ssl.conf"
    echo ""
    
    echo -e "${YELLOW}🔧 Next Steps:${NC}"
    echo ""
    echo "1. 📡 Distribute certificates to all servers:"
    echo "   $SSL_DIR/distribute-certs.sh"
    echo ""
    echo "2. 🔄 Update MongoDB configuration on each server:"
    echo "   sudo cp $SSL_DIR/mongod-ssl.conf /etc/mongod.conf"
    echo "   sudo systemctl restart mongod"
    echo ""
    echo "3. 🧪 Test SSL connections:"
    echo "   $SSL_DIR/test-ssl-connection.sh"
    echo ""
    
    echo -e "${BLUE}🔗 SSL Connection Strings:${NC}"
    echo ""
    echo "Basic SSL:"
    echo "mongodb://username:password@database.vdohide.dev:27017/dbname?replicaSet=rs0&authSource=admin&tls=true&tlsInsecure=true"
    echo ""
    echo "Replica Set SSL:"
    echo "mongodb://username:password@91.99.163.168:27017,91.99.209.211:27017,46.62.169.124:27017/dbname?replicaSet=rs0&authSource=admin&tls=true&tlsInsecure=true"
    echo ""
    echo "Production SSL (with certificate validation):"
    echo "mongodb://username:password@database.vdohide.dev:27017/dbname?replicaSet=rs0&authSource=admin&tls=true&tlsCertificateKeyFile=/opt/mongodb/ssl/mongodb.pem&tlsCAFile=/opt/mongodb/ssl/ca-bundle.crt"
    echo ""
    
    print_warning "Certificate Details:"
    echo "- Valid for: $CERT_VALIDITY_DAYS days"
    echo "- Domains: $DOMAINS"
    echo "- IP Addresses: $IP_ADDRESSES"
    echo "- Algorithm: RSA 4096-bit"
    echo ""
    
    print_status "Log file: $LOG_FILE"
}

# Main function
main() {
    print_header "MONGODB SSL CERTIFICATE CREATION"
    
    # Create log file
    touch $LOG_FILE
    chmod 644 $LOG_FILE
    
    print_status "Starting SSL certificate creation process..."
    
    # Run setup steps
    check_root
    check_dependencies
    create_ssl_directory
    create_openssl_config
    generate_private_key
    generate_csr
    generate_certificate
    create_pem_file
    create_ca_certificate
    set_permissions
    verify_certificates
    create_mongodb_ssl_config
    create_distribution_script
    create_connection_test
    show_completion_summary
    
    print_status "SSL certificate setup completed successfully!"
}

# Run main function
main "$@"
