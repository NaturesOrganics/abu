all: install

install: config
	install -m 0755 abu.sh /usr/local/sbin/abu

config:
	test -e /etc/abu.conf || install -m 0640 abu.conf /etc/abu.conf
