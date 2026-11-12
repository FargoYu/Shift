"""Export the second-version character GIFs with Pillow.

Run `python tools/export_character_animations.py` from the project directory.
"""

import json
from pathlib import Path

from PIL import Image, ImageSequence


PROJECT = Path(__file__).resolve().parents[1]
ASSETS = PROJECT / "assets" / "character_related"
FRAME_WIDTH, FRAME_HEIGHT = 56, 40
FPS = 10

# Align the unarmed poses to the center and ground line of the shared canvas.
ORIGINS = {"player": (19, 7), "boss": (20, 4)}
# This fixed patch in the original Boss canvas is outside the artwork.
BOSS_WHITE_PATCH = (39, 1, 47, 3)


def read_frames(source, role):
    x, y = ORIGINS[role]
    frames = []
    with Image.open(source) as gif:
        for source_frame in ImageSequence.Iterator(gif):
            # Sequential decoding composites GIF updates before conversion to RGBA.
            frame = source_frame.convert("RGBA")
            if role == "boss":
                frame.paste((0, 0, 0, 0), BOSS_WHITE_PATCH)
            bounds = frame.getchannel("A").getbbox()
            if bounds:
                left, top, right, bottom = bounds
                if not (
                    0 <= x + left < x + right <= FRAME_WIDTH
                    and 0 <= y + top < y + bottom <= FRAME_HEIGHT
                ):
                    raise ValueError(f"{source}, frame {len(frames) + 1} exceeds the canvas")
            duration_ms = source_frame.info.get("duration", 0)
            if duration_ms <= 0:
                raise ValueError(f"{source}, frame {len(frames) + 1} needs a positive duration")
            normalized = Image.new("RGBA", (FRAME_WIDTH, FRAME_HEIGHT))
            normalized.paste(frame, (x, y))
            frames.append((normalized, duration_ms))
    return frames


def export_role(role):
    folder = ASSETS / role
    sources = sorted(
        path for path in folder.rglob("*")
        if path.suffix.lower() == ".gif" and "old" not in path.relative_to(folder).parts
    )
    if len({source.stem for source in sources}) != len(sources):
        raise ValueError(f"Duplicate animation names for {role}")

    textures = []
    regions = []
    animations = []
    for texture_id, source in enumerate(sources, start=1):
        frames = read_frames(source, role)
        output = source.with_suffix(".png")
        sheet = Image.new("RGBA", (FRAME_WIDTH * len(frames), FRAME_HEIGHT))
        frame_entries = []
        for index, (frame, duration_ms) in enumerate(frames):
            x = index * FRAME_WIDTH
            sheet.paste(frame, (x, 0))
            region_id = f"{source.stem}_{index}"
            regions.append(
                f'[sub_resource type="AtlasTexture" id="{region_id}"]\n'
                f'atlas = ExtResource("{texture_id}")\n'
                f'region = Rect2({x}, 0, {FRAME_WIDTH}, {FRAME_HEIGHT})'
            )
            relative_duration = duration_ms * FPS / 1000
            frame_entries.append(
                f'{{\n"duration": {relative_duration},\n'
                f'"texture": SubResource("{region_id}")\n}}'
            )
        sheet.save(output)
        resource_path = json.dumps(f"res://{output.relative_to(PROJECT).as_posix()}")
        textures.append(f'[ext_resource type="Texture2D" path={resource_path} id="{texture_id}"]')
        loop = "true" if source.stem.endswith("_idle") else "false"
        entries = ", ".join(frame_entries)
        animations.append(
            f'{{\n"frames": [{entries}],\n"loop": {loop},\n'
            f'"name": &{json.dumps(source.stem)},\n"speed": {float(FPS)}\n}}'
        )

    header = f'[gd_resource type="SpriteFrames" load_steps={1 + len(textures) + len(regions)} format=3]'
    resource = '[resource]\nanimations = [' + ", ".join(animations) + "]"
    contents = "\n\n".join([header, "\n".join(textures), *regions, resource])
    (folder / "sprite_frames.tres").write_text(contents + "\n", encoding="utf-8")
    print(f"{role}: {len(sources)} sprite sheets, {len(regions)} frames")


if __name__ == "__main__":
    for character in ORIGINS:
        export_role(character)
