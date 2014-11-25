all: install

install:
	install -m 0755 abu.sh /usr/local/sbin/abu
	install -m 0644 abu.conf /etc/abu.conf
