#filter substitution

# Win7: AppVendor, AppName, and AppVersion must match the application.ini values
# of Vendor, Name, and Version. These values are used in registering shortcuts
# with the taskbar. ExplicitAppUserModelID registration when the app launches is
# handled in widget/src/windows/WinTaskbar.cpp.

!define AppVendor             "Zotero"
!define AppName               "Standalone"
!define AppVersion            "{{VERSION}}"
!define AppUserModelID        "${AppVendor}.${AppName}.${AppVersion}"
!define GREVersion            2.0
!define AB_CD                 "en-US"

!define FileMainEXE           "zotero.exe"
!define WindowClass           "ZoteroMessageWindow"
!define AppRegName            "Zotero"

!define BrandShortName        "Zotero"
!define PreReleaseSuffix      ""
!define BrandFullName         "${BrandFullNameInternal}${PreReleaseSuffix}"

!define NO_UNINSTALL_SURVEY

# LSP_CATEGORIES is the permitted LSP categories for the application. Each LSP
# category value is ANDed together to set multiple permitted categories.
# See http://msdn.microsoft.com/en-us/library/ms742253%28VS.85%29.aspx
# The value below removes all LSP categories previously set.
!define LSP_CATEGORIES "0x00000000"

# NO_INSTDIR_FROM_REG is defined for pre-releases which have a PreReleaseSuffix
# (e.g. Alpha X, Beta X, etc.) to prevent finding a non-default installation
# directory in the registry and using that as the default. This prevents
# Beta releases built with official branding from finding an existing install
# of an official release and defaulting to its installation directory.
!if "@PRE_RELEASE_SUFFIX@" != ""
!define NO_INSTDIR_FROM_REG
!endif

# ARCH is used when it is necessary to differentiate the x64 registry keys from
# the x86 registry keys (e.g. the uninstall registry key).
!define ARCH "x86"
!define MinSupportedVer "Microsoft Windows 2000"

# File details shared by both the installer and uninstaller
VIProductVersion "1.0.0.0"
VIAddVersionKey "ProductName"     "${BrandShortName}"
VIAddVersionKey "CompanyName"     "${CompanyName}"
VIAddVersionKey "LegalCopyright"  "${CompanyName}"
VIAddVersionKey "FileVersion"     "${AppVersion}"
VIAddVersionKey "ProductVersion"  "${AppVersion}"
# Comments is not used but left below commented out for future reference
# VIAddVersionKey "Comments"        "Comments"

# These are used for keeping track of user preferences. They are set to a
# default value in the installer's .OnInit callback, and then conditionally
# modified through the UI or an .ini file.

!define DESKTOP_SHORTCUT_DISABLED 0
!define DESKTOP_SHORTCUT_ENABLED  1
!define DESKTOP_SHORTCUT_DEFAULT  ${DESKTOP_SHORTCUT_ENABLED}
