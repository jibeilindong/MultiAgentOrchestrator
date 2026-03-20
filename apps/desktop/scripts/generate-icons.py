from pathlib import Path
from tempfile import TemporaryDirectory
import subprocess

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parent.parent
BUILD_RESOURCES = ROOT / "buildResources"
ICONSET = BUILD_RESOURCES / "icon.iconset"
PNG_PATH = BUILD_RESOURCES / "icon.png"
ICO_PATH = BUILD_RESOURCES / "icon.ico"
ICNS_PATH = BUILD_RESOURCES / "icon.icns"

SIZES = [16, 32, 64, 128, 256, 512, 1024]
BACKGROUND_TOP = (15, 118, 110)
BACKGROUND_BOTTOM = (16, 33, 50)
NODE_FILL = (243, 247, 255)
EDGE_COLOR = (125, 211, 252)
NODE_INNER = (15, 118, 110)


def lerp_channel(start: int, end: int, ratio: float) -> int:
    return int(round(start + (end - start) * ratio))


def gradient_background(size: int) -> Image.Image:
    image = Image.new("RGBA", (size, size))
    pixels = image.load()
    for y in range(size):
        ratio = y / max(size - 1, 1)
        row_color = tuple(
            lerp_channel(BACKGROUND_TOP[index], BACKGROUND_BOTTOM[index], ratio) for index in range(3)
        ) + (255,)
        for x in range(size):
            pixels[x, y] = row_color
    return image


def draw_icon(size: int) -> Image.Image:
    image = gradient_background(size)
    mask = Image.new("L", (size, size), 0)
    mask_draw = ImageDraw.Draw(mask)
    radius = int(size * 0.22)
    mask_draw.rounded_rectangle((0, 0, size, size), radius=radius, fill=255)
    rounded = Image.new("RGBA", (size, size))
    rounded.paste(image, (0, 0), mask)

    draw = ImageDraw.Draw(rounded)
    node_radius = int(size * 0.085)
    center_radius = int(size * 0.093)
    line_width = max(8, int(size * 0.046))
    inner_radius = max(5, int(size * 0.028))

    left = (int(size * 0.28), int(size * 0.29))
    right = (int(size * 0.72), int(size * 0.29))
    bottom = (int(size * 0.5), int(size * 0.73))

    draw.line((left, right), fill=EDGE_COLOR, width=line_width)
    draw.line((left, bottom), fill=EDGE_COLOR, width=line_width)
    draw.line((right, bottom), fill=EDGE_COLOR, width=line_width)

    for center, radius_value in ((left, node_radius), (right, node_radius), (bottom, center_radius)):
        draw.ellipse(
            (
                center[0] - radius_value,
                center[1] - radius_value,
                center[0] + radius_value,
                center[1] + radius_value,
            ),
            fill=NODE_FILL,
        )
        draw.ellipse(
            (
                center[0] - inner_radius,
                center[1] - inner_radius,
                center[0] + inner_radius,
                center[1] + inner_radius,
            ),
            fill=NODE_INNER,
        )

    return rounded


def save_png_assets() -> None:
    BUILD_RESOURCES.mkdir(parents=True, exist_ok=True)
    image_1024 = draw_icon(1024)
    image_1024.save(PNG_PATH, format="PNG")
    image_1024.save(ICO_PATH, format="ICO", sizes=[(size, size) for size in (16, 24, 32, 48, 64, 128, 256)])


def save_icns() -> None:
    with TemporaryDirectory() as temporary_directory:
        iconset_dir = Path(temporary_directory) / "icon.iconset"
        iconset_dir.mkdir(parents=True, exist_ok=True)

        for size in (16, 32, 128, 256, 512):
            image = draw_icon(size)
            image.save(iconset_dir / f"icon_{size}x{size}.png", format="PNG")
            image.resize((size * 2, size * 2), Image.LANCZOS).save(
                iconset_dir / f"icon_{size}x{size}@2x.png",
                format="PNG",
            )

        subprocess.run(
            ["iconutil", "-c", "icns", str(iconset_dir), "-o", str(ICNS_PATH)],
            check=True,
        )


def main() -> None:
    save_png_assets()
    save_icns()
    print(f"generated icons in {BUILD_RESOURCES}")


if __name__ == "__main__":
    main()
