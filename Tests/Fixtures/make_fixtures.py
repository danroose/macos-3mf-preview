#!/usr/bin/env python3
"""Generates the small synthetic 3MF files used by the unit tests.

Run from the repo root:  python3 -I Tests/Fixtures/make_fixtures.py
Each file exercises one slicer flavour; the expected values live in Tests/ThreeMFModelTests.swift.
"""
import os
import struct
import zipfile
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))

CONTENT_TYPES = """<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
 <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
 <Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/>
 <Default Extension="png" ContentType="image/png"/>
</Types>"""

RELS = """<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
 <Relationship Target="/3D/3dmodel.model" Id="rel0" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>
 {extra}
</Relationships>"""

THUMB_REL = '<Relationship Target="/Metadata/thumbnail.png" Id="rel1" ' \
            'Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/thumbnail"/>'


def png(width, height, rgb):
    """A solid-color PNG, so tests can tell which embedded image was picked."""
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    raw = b"".join(b"\x00" + bytes(rgb) * width for _ in range(height))
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw))
            + chunk(b"IEND", b""))


def cube_mesh(size=10.0, tri_attrs=None):
    """A cube from (0,0,0) to (size,size,size): 8 vertices, 12 triangles."""
    s = size
    verts = [(0, 0, 0), (s, 0, 0), (s, s, 0), (0, s, 0), (0, 0, s), (s, 0, s), (s, s, s), (0, s, s)]
    tris = [(0, 2, 1), (0, 3, 2), (4, 5, 6), (4, 6, 7), (0, 1, 5), (0, 5, 4),
            (1, 2, 6), (1, 6, 5), (2, 3, 7), (2, 7, 6), (3, 0, 4), (3, 4, 7)]
    tri_attrs = tri_attrs or {}
    v = "\n".join(f'     <vertex x="{x}" y="{y}" z="{z}"/>' for x, y, z in verts)
    t = "\n".join(f'     <triangle v1="{a}" v2="{b}" v3="{c}"{tri_attrs.get(i, "")}/>' for i, (a, b, c) in enumerate(tris))
    return f"   <mesh>\n    <vertices>\n{v}\n    </vertices>\n    <triangles>\n{t}\n    </triangles>\n   </mesh>"


def model(resources, build, ns=""):
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<model unit="millimeter" xml:lang="en-US" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02"{ns}>
 <resources>
{resources}
 </resources>
 <build>
{build}
 </build>
</model>"""


def write(name, files, compression=zipfile.ZIP_DEFLATED):
    path = os.path.join(HERE, name)
    with zipfile.ZipFile(path, "w", compression) as z:
        for entry, data in files.items():
            z.writestr(entry, data)
    print("wrote", path)


def core_cube(name, compression):
    """Plain 3MF core spec: basematerials color, a thumbnail found via _rels/.rels."""
    mesh = cube_mesh(tri_attrs={0: ' pid="1" p1="1"'})
    resources = ('  <basematerials id="1">\n'
                 '   <base name="Red PLA" displaycolor="#FF0000FF"/>\n'
                 '   <base name="Green PLA" displaycolor="#00FF00"/>\n'
                 '  </basematerials>\n'
                 f'  <object id="2" type="model" pid="1" pindex="0">\n{mesh}\n  </object>')
    write(name, {
        "[Content_Types].xml": CONTENT_TYPES,
        "_rels/.rels": RELS.format(extra=THUMB_REL),
        "3D/3dmodel.model": model(resources, '  <item objectid="2"/>'),
        "Metadata/thumbnail.png": png(4, 4, (0, 0, 255)),
    }, compression)


def bambu():
    """Bambu Studio layout: mesh in a sub-file via p:path components, item transform,
    per-triangle paint_color, object extruder in model_settings.config, filament colors in project_settings."""
    ns = (' xmlns:BambuStudio="http://schemas.bambulab.com/package/2021"'
          ' xmlns:p="http://schemas.microsoft.com/3dmanufacturing/production/2015/06" requiredextensions="p"')
    painted = {0: ' paint_color="8"', 1: ' paint_color="8"', 2: ' paint_color="48883"'}
    sub = model(f'  <object id="1" type="model">\n{cube_mesh(tri_attrs=painted)}\n  </object>', "", ns)
    main = model('  <object id="2" type="model">\n   <components>\n'
                 '    <component p:path="/3D/Objects/object_1.model" objectid="1" transform="1 0 0 0 1 0 0 0 1 0 0 0"/>\n'
                 '   </components>\n  </object>',
                 '  <item objectid="2" transform="1 0 0 0 1 0 0 0 1 100 50 10" printable="1"/>', ns)
    settings = """<?xml version="1.0" encoding="UTF-8"?>
<config>
  <object id="2">
    <metadata key="name" value="cube.stl"/>
    <metadata key="extruder" value="3"/>
    <part id="1" subtype="normal_part">
      <metadata key="name" value="cube.stl"/>
    </part>
  </object>
</config>"""
    write("bambu-components.3mf", {
        "[Content_Types].xml": CONTENT_TYPES,
        "_rels/.rels": RELS.format(extra=""),
        "3D/3dmodel.model": main,
        "3D/Objects/object_1.model": sub,
        "Metadata/model_settings.config": settings,
        "Metadata/project_settings.config": '{"filament_colour": ["#111111", "#22FF22", "#3333FF"]}',
        "Metadata/pick_1.png": png(2, 2, (0, 0, 0)),
        "Metadata/plate_1.png": png(8, 6, (255, 128, 0)),
        "Metadata/plate_1_small.png": png(2, 2, (9, 9, 9)),
    })


def prusa():
    """PrusaSlicer layout: volumes as triangle ranges with their own extruder, mmu_segmentation paint,
    extruder_colour with an empty slot that falls back to filament_colour. No embedded thumbnail."""
    ns = ' xmlns:slic3rpe="http://schemas.slic3r.org/3mf/2017/06"'
    mesh = cube_mesh(tri_attrs={11: ' slic3rpe:mmu_segmentation="8"'})
    main = model(f'  <object id="1" type="model">\n{mesh}\n  </object>', '  <item objectid="1"/>', ns)
    config = """<?xml version="1.0" encoding="UTF-8"?>
<config>
 <object id="1" instances_count="1">
  <metadata type="object" key="extruder" value="1"/>
  <volume firstid="0" lastid="3">
   <metadata type="volume" key="extruder" value="2"/>
  </volume>
  <volume firstid="4" lastid="11">
   <metadata type="volume" key="name" value="rest"/>
  </volume>
 </object>
</config>"""
    write("prusa-volumes.3mf", {
        "[Content_Types].xml": CONTENT_TYPES,
        "_rels/.rels": RELS.format(extra=""),
        "3D/3dmodel.model": main,
        "Metadata/Slic3r_PE.config": "; generated by PrusaSlicer\n; extruder_colour = #FF0000;\n; filament_colour = #00FF00;#0000FF\n",
        "Metadata/Slic3r_PE_model.config": config,
    })


if __name__ == "__main__":
    core_cube("core-cube.3mf", zipfile.ZIP_DEFLATED)
    core_cube("core-cube-stored.3mf", zipfile.ZIP_STORED)
    bambu()
    prusa()
    with open(os.path.join(HERE, "not-a-zip.3mf"), "w") as f:
        f.write("this is not a 3mf file\n")
    print("wrote not-a-zip.3mf")
