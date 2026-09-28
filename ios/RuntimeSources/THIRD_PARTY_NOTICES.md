# Embedded OpenJDK runtime notices

The optional iOS embedded-JVM support in dartotsu_extension_bridge contains:

- OpenJDK Mobile and the OpenJDK class library, distributed under GPLv2 with
  the Classpath Exception. Source and license texts are available from
  <https://github.com/openjdk/mobile> and
  <https://github.com/openjdk-mobile/ios-tools>. The pinned device build is
  reused from the `embedded-openjdk-ios13-v16` release at
  <https://github.com/1Selxo/Mangatan>.
- The native loader / bootstrap-thread approach is adapted from
  `m_extension_server` (MPL-2.0),
  <https://github.com/kodjodevf/m_extension_server>.

The extension backend JARs themselves are downloaded at runtime and are not
part of this bundle. These components are provided without warranty.
