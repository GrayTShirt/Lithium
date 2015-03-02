%define modulename Lithium

Name:      lithium
Version:   1.0.0
Release:   1
Vendor:    Synacor
Summary:   Lithium Selenium Grid Replacement
License:   GPLv3+
Group:     System Environment/Daemons
URL:       http://github.com/GrayTShirt/Lithium
BuildRoot: %{_tmppath}/%{name}-root
Source:    %{modulename}-%{version}.tar.gz
BuildArch: noarch

%description
Lithium is a not-quite drop-in replacement for the Selenium Grid Server. Instead of
proxying sessions, Lithium will forward sessions on to the Session's node, relieving
network bottlenecks, and proxy timeout issues associated with large grid deployments.


%pre
USER=lithium
GROUP=$USER
HOMEDIR=/var/$USER
getent group $GROUP >/dev/null || groupadd -r $GROUP
getent passwd $USER >/dev/null || \
	useradd -r -g $GROUP -d $HOMEDIR -s /sbin/nologin \
		-c "lithium daemon" $USER


%prep
%setup -q -n %{modulename}-%{version}


%build
CFLAGS="$RPM_OPT_FLAGS" perl Makefile.PL INSTALLDIRS=vendor INSTALL_BASE=''
make

%check
make test


%clean
rm -rf $RPM_BUILD_ROOT


%install
rm -rf $RPM_BUILD_ROOT
make install DESTDIR=$RPM_BUILD_ROOT

if [ -f rpm_files/etc/lithium.conf.dist ]; then mv rpm_files/etc/lithium.conf.dist rpm_files/etc/lithium.conf; fi
if [ -d rpm_files ]; then cp -r rpm_files/* $RPM_BUILD_ROOT; fi

[ -x /usr/lib/rpm/brp-compress ] && /usr/lib/rpm/brp-compress

find $RPM_BUILD_ROOT -name .packlist     -print0 | xargs -0 /bin/rm -f
find $RPM_BUILD_ROOT -name perllocal.pod -print0 | xargs -0 /bin/rm -f
find $RPM_BUILD_ROOT -name rpm_files     -print0 | xargs -0 /bin/rm -fr

find $RPM_BUILD_ROOT -type f -print | \
    sed "s@^$RPM_BUILD_ROOT@@g" | \
    grep -v perllocal.pod | \
    grep -v "\\.packlist" > %{modulename}-%{version}-filelist

if [ "$(cat %{modulename}-%{version}-filelist)X" = "X" ] ; then
    echo "ERROR: EMPTY FILE LIST"
    exit -1
fi


%pre


%preun


%post


%postun


%files -f %{modulename}-%{version}-filelist
%defattr(-,root,root)
%config /etc/sysconfig/nlma
%config /etc/lithium.conf

