all: install

install:
	install -m 0755 src/abu.sh /usr/local/sbin/abu

config:
	install -m 0644 abu.conf /etc/abu.conf
