.PHONY: all clean install

all:
clean:

install:
	install -m755 -d $(DESTDIR)/usr/bin
	install -m755 cow-build.sh $(DESTDIR)/usr/bin/cow-build
	install -m755 cow-update.sh $(DESTDIR)/usr/bin/cow-update
