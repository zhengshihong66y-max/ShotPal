#!/usr/bin/env python3
import unittest
from verify_download_runtime import dylib_dependencies


class DependencyParsingTests(unittest.TestCase):
    def test_install_id_is_not_a_dependency(self):
        commands = """
          cmd LC_ID_DYLIB
         name /build/machine/libomp.dylib (offset 24)
          cmd LC_LOAD_DYLIB
         name /usr/lib/libSystem.B.dylib (offset 24)
          cmd LC_LOAD_WEAK_DYLIB
         name @loader_path/libhelper.dylib (offset 24)
        """
        self.assertEqual(list(dylib_dependencies(commands)),
                         ["/usr/lib/libSystem.B.dylib", "@loader_path/libhelper.dylib"])

    def test_real_external_load_is_not_hidden(self):
        commands = """
          cmd LC_LOAD_DYLIB
         name /opt/homebrew/lib/libbad.dylib (offset 24)
          cmd LC_REEXPORT_DYLIB
         name /build/machine/libbad.dylib (offset 24)
        """
        self.assertEqual(list(dylib_dependencies(commands)),
                         ["/opt/homebrew/lib/libbad.dylib", "/build/machine/libbad.dylib"])


if __name__ == "__main__":
    unittest.main()
