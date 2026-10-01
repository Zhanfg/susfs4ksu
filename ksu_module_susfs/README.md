# SUSFS control module

The controller prefers a working `ksud susfs` interface, including ReSukiSU.
It verifies the reported SUSFS version and variant before choosing a backend.
The fallback helper is installed as `bin/ksu_susfs` inside the module directory.
Installation and removal preserve manager-owned binaries and hard links.

The default configuration is inert. Configure `config/default.conf`, then use
`controller.sh status` to inspect backend, version, variant and features.
