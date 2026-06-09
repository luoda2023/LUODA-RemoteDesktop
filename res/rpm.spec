Name:       luoda
Version:    1.4.6
Release:    0
Summary:    RPM package
License:    GPL-3.0
URL:        https://luoda.com
Vendor:     luoda <info@luoda.com>
Requires:   gtk3 libxcb libXfixes alsa-lib libva2 pam gstreamer1-plugins-base
Recommends: libayatana-appindicator-gtk3 libxdo

# https://docs.fedoraproject.org/en-US/packaging-guidelines/Scriptlets/

%description
The best open-source remote desktop client software, written in Rust.

%prep
# we have no source, so nothing here

%build
# we have no source, so nothing here

%global __python %{__python3}

%install
mkdir -p %{buildroot}/usr/bin/
mkdir -p %{buildroot}/usr/share/luoda/
mkdir -p %{buildroot}/usr/share/luoda/files/
mkdir -p %{buildroot}/usr/share/icons/hicolor/256x256/apps/
mkdir -p %{buildroot}/usr/share/icons/hicolor/scalable/apps/
install -m 755 $HBB/target/release/luoda %{buildroot}/usr/bin/luoda
install $HBB/libsciter-gtk.so %{buildroot}/usr/share/luoda/libsciter-gtk.so
install $HBB/res/luoda.service %{buildroot}/usr/share/luoda/files/
install $HBB/res/128x128@2x.png %{buildroot}/usr/share/icons/hicolor/256x256/apps/luoda.png
install $HBB/res/scalable.svg %{buildroot}/usr/share/icons/hicolor/scalable/apps/luoda.svg
install $HBB/res/luoda.desktop %{buildroot}/usr/share/luoda/files/
install $HBB/res/luoda-link.desktop %{buildroot}/usr/share/luoda/files/

%files
/usr/bin/luoda
/usr/share/luoda/libsciter-gtk.so
/usr/share/luoda/files/luoda.service
/usr/share/icons/hicolor/256x256/apps/luoda.png
/usr/share/icons/hicolor/scalable/apps/luoda.svg
/usr/share/luoda/files/luoda.desktop
/usr/share/luoda/files/luoda-link.desktop
/usr/share/luoda/files/__pycache__/*

%changelog
# let's skip this for now

%pre
# can do something for centos7
case "$1" in
  1)
    # for install
  ;;
  2)
    # for upgrade
    systemctl stop luoda || true
  ;;
esac

%post
cp /usr/share/luoda/files/luoda.service /etc/systemd/system/luoda.service
cp /usr/share/luoda/files/luoda.desktop /usr/share/applications/
cp /usr/share/luoda/files/luoda-link.desktop /usr/share/applications/
systemctl daemon-reload
systemctl enable luoda
systemctl start luoda
update-desktop-database

%preun
case "$1" in
  0)
    # for uninstall
    systemctl stop luoda || true
    systemctl disable luoda || true
    rm /etc/systemd/system/luoda.service || true
  ;;
  1)
    # for upgrade
  ;;
esac

%postun
case "$1" in
  0)
    # for uninstall
    rm /usr/share/applications/luoda.desktop || true
    rm /usr/share/applications/luoda-link.desktop || true
    update-desktop-database
  ;;
  1)
    # for upgrade
  ;;
esac
