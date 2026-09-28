extern "C" void loadfunctions(void);

extern "C" __attribute__((visibility("default")))
void MExtensionServerOpenJDKLoadFunctions(void) {
  loadfunctions();
}
