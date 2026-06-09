Name:       luoda
Version:    1.4.6
Release:    0
Summary:    RPM package
License:    GPL-3.0
URL:        https://luoda.com
Vendor:     luoda <info@luoda.com>
Requires:   gtk3 libxcb libXfixes alsa-lib libva pam gstreamer1-plugins-base
Recommends: libayatana-appindicator-gtk3 libxdo
Provides:   libdesktop_drop_plugin.so()(64bit), libdesktop_multi_window_plugin.so()(64bit), libfile_selector_linux_plugin.so()(64bit), libflutter_custom_cursor_plugin.so()(64bit), libflutter_linux_gtk.so()(64bit), libscreen_retriever_plugin.so()(64bit), libtray_manager_plugin.so()(64bit), liburl_launcher_linux_plugin.so()(64bit), libwindow_manager_plugin.so()(64bit), libwindow_size_plugin.so()(64bit), libtexture_rgba_renderer_plugin.so()(64bit)

# https://docs.fedoraproject.org/en-US/packaging-guidelines/Scriptlets/

%description
The best open-source remote desktop client software, written in Rust.

%prep
# we have no source, so nothing here

%build
# we have no source, so nothing here

# %global __python %{__python3}

%install

mkdir -p "%{buildroot}/usr/share/luoda" && cp -r ${HBB}/flutter/build/linux/x64/release/bundle/* -t "%{buildroot}/usr/share/luoda"
mkdir -p "%{buildroot}/usr/bin"
install -Dm 644 $HBB/res/luoda.service -t "%{buildroot}/usr/share/luoda/files"
install -Dm 644 $HBB/res/luoda.desktop -t "%{buildroot}/usr/share/luoda/files"
install -Dm 644 $HBB/res/luoda-link.desktop -t "%{buildroot}/usr/share/luoda/files"
install -Dm 644 $HBB/res/128x128@2x.png "%{buildroot}/usr/share/icons/hicolor/256x256/apps/luoda.png"
install -Dm 644 $HBB/res/scalable.svg "%{buildroot}/usr/share/icons/hicolor/scalable/apps/luoda.svg"

%files
/usr/share/luoda/*
/usr/share/luoda/files/luoda.service
/usr/share/icons/hicolor/256x256/apps/luoda.png
/usr/share/icons/hicolor/scalable/apps/luoda.svg
/usr/share/luoda/files/luoda.desktop
/usr/share/luoda/files/luoda-link.desktop

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
ln -sf /usr/share/luoda/luoda /usr/bin/luoda
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
    rm /usr/bin/luoda || true
    rmdir /usr/lib/luoda || true
    rmdir /usr/local/luoda || true
    rmdir /usr/share/luoda || true
    rm /usr/share/applications/luoda.desktop || true
    rm /usr/share/applications/luoda-link.desktop || true
    update-desktop-database
  ;;
  1)
    # for upgrade
    rmdir /usr/lib/luoda || true
    rmdir /usr/local/luoda || true
  ;;
esac
