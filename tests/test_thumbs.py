import importlib.util
import pathlib
import tempfile
import unittest
from unittest.mock import patch

from PIL import Image

spec = importlib.util.spec_from_file_location(
    "make_thumbs", pathlib.Path(__file__).resolve().parents[1] / "tools/make_thumbs.py"
)
thumbs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(thumbs)


class Thumbnails(unittest.TestCase):
    def test_metadata_id_works_without_workshop_suffix(self):
        with tempfile.TemporaryDirectory() as tmp:
            meta = pathlib.Path(tmp) / "metadata.xml"
            meta.write_text("<metadata><id>3819892905</id></metadata>")
            self.assertEqual(thumbs.workshop_id("better-mods-menu", meta), "3819892905")

    def test_invalid_metadata_falls_back_to_folder_id(self):
        with tempfile.TemporaryDirectory() as tmp:
            meta = pathlib.Path(tmp) / "metadata.xml"
            meta.write_text("broken XML")
            self.assertEqual(thumbs.workshop_id("example_123456789", meta), "123456789")
            self.assertIsNone(thumbs.workshop_id("local-mod", meta))

    def test_workshop_preview_takes_priority_and_is_cached_by_id(self):
        import io
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            mod = root / "mods" / "renamed-mod"
            mod.mkdir(parents=True)
            (mod / "metadata.xml").write_text("<metadata><id>123456789</id></metadata>")
            Image.new("RGB", (96, 96), "red").save(mod / "thumb.png")
            remote = io.BytesIO()
            Image.new("RGB", (96, 96), "blue").save(remote, format="JPEG")
            args = ["--mods-dir", str(mod.parent), "--output", str(root / "out"), "--download"]
            with patch.object(thumbs, "fetch_previews", return_value={"123456789": remote.getvalue()}):
                self.assertEqual(thumbs.main(args), 0)
            with Image.open(root / "out" / "workshop" / "123456789.png") as im:
                self.assertEqual(im.format, "PNG")
                self.assertGreater(im.getpixel((48, 48))[2], 250)
            # Offline regeneration must leave the downloaded preview intact.
            args.remove("--download")
            self.assertEqual(thumbs.main(args), 0)
            self.assertTrue((root / "out" / "workshop" / "123456789.png").is_file())

    def test_ascii_folder_name_matches_lua(self):
        self.assertEqual(thumbs.key_for("mod name_123-abc"), "mod_name_123-abc")

    def test_unicode_folder_name_matches_lua_byte_replacement(self):
        # Lua gsub replaces each UTF-8 byte, not each Unicode character.
        self.assertEqual(thumbs.key_for("мод"), "______")
        self.assertEqual(thumbs.key_for("café"), "caf__")

    def test_preview_crops_center_and_outputs_rgba(self):
        source = Image.new("RGB", (300, 100), "red")
        source.paste("blue", (100, 0, 200, 100))
        preview = thumbs.to_thumb(source)
        self.assertEqual(preview.size, (96, 96))
        self.assertEqual(preview.mode, "RGBA")
        self.assertEqual(preview.getpixel((0, 0)), (0, 0, 255, 255))
        self.assertEqual(preview.getpixel((95, 95)), (0, 0, 255, 255))


if __name__ == "__main__":
    unittest.main()
