all: install

install:
	install -m 0755 src/abu.sh /usr/local/sbin/abu

conf:
	install -m 0644 abu.conf /etc/abu.conf
