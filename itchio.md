<h1>P1Xel Editor</h1>

<p><strong>A must-have pixel art, tile, sprite, palette, and map editor for Game Boy Color developers!</strong></p>

<p>
P1Xel Editor is a focused tool for making retro 8×8 indexed art, tilesets, sprites, palettes, and maps for Game Boy Color-style games. It keeps the workflow simple: draw tiny tiles, assign palettes, build maps, place sprites, and export data for your engine.
</p>

<h2>Perfect for Game Boy Color projects</h2>

<p>P1Xel Editor uses a classic indexed-colour workflow:</p>

<ul>
  <li>8×8 tiles and sprites</li>
  <li>4 colours per palette</li>
  <li>8 palettes per palette bank</li>
  <li>Multiple biome palette banks</li>
  <li>Game Boy Color-style 2bpp export</li>
</ul>

<p>
Make your art once, then swap palettes for different worlds, biomes, or moods.
</p>

<h2>Key features</h2>

<ul>
  <li><strong>Tile editor</strong> for clean 8×8 background tiles</li>
  <li><strong>Sprite editor</strong> with colour index 0 used as transparency</li>
  <li><strong>Map editor</strong> for building tile maps and placing sprite instances</li>
  <li><strong>4 project slots</strong> available with F1–F4 for multiple files, variations, or sketch-pad experiments</li>
  <li><strong>4 map banks</strong> for different levels or biomes</li>
  <li><strong>4 palette banks</strong> for biome/theme colour sets</li>
  <li><strong>8 palettes per bank</strong>, each with 4 colours</li>
  <li><strong>Palette preview and editing</strong> with RGB sliders</li>
  <li><strong>3×3 quick-select grid</strong> for easy tile and sprite preview/selection</li>
  <li><strong>Tile/sprite library</strong> with add, duplicate, delete, paging, and slot swapping</li>
  <li><strong>Pixel, fill, and line tools</strong> for fast tiny-art editing</li>
  <li><strong>Per-tile palette assignment</strong></li>
  <li><strong>Map palette overrides</strong> per cell</li>
  <li><strong>Horizontal and vertical flips</strong> for map tiles and sprites</li>
  <li><strong>Tile flags / logic data</strong> for collision or gameplay use</li>
  <li><strong>Copy/paste pixel data between projects</strong> using COPY PIX and PASTE PIX</li>
  <li><strong>Game Boy Color export</strong> to engine_export.p1xb</li>
  <li><strong>RGBDS include export</strong> for easy GBC engine integration</li>
  <li><strong>Steam Deck-friendly fullscreen layout</strong></li>
</ul>

<h2>Four project slots</h2>

<p>
Work on a few files without leaving the editor. P1Xel Editor has four quick project slots mapped to <strong>F1</strong>, <strong>F2</strong>, <strong>F3</strong>, and <strong>F4</strong>.
</p>

<p>
Each slot is saved as its own file, from <strong>art_data-f1.p1x</strong> through <strong>art_data-f4.p1x</strong>. Use one slot for your main project, another for alternate versions, and another as a sketch pad for quick experiments.
</p>

<h2>Copy pixel data between projects</h2>

<p>
Need to reuse a tile or sprite from another project?
</p>

<p>
Use <strong>COPY PIX</strong> to copy the raw 8×8 pixel pattern, open another project, then use <strong>PASTE PIX</strong>. This copies only the pixel indices, so your palette assignments stay flexible.
</p>

<h2>Export to your GBC engine</h2>

<p>P1Xel Editor exports:</p>

<ul>
  <li>palettes</li>
  <li>2bpp tile graphics</li>
  <li>tile maps</li>
  <li>attribute maps</li>
  <li>logic/collision maps</li>
  <li>sprite placements</li>
</ul>

<p>
The export is made for Game Boy Color-style engines and includes an RGBDS .inc file for direct use in assembly projects.
</p>

<p>
An example Game Boy Color project that imports and uses the exported data is included as a separate download. Use it as a starting point or reference for your own engine integration.
</p>

<p>
See <strong>GBC.md</strong> in the package for the full export format and import guide.
</p>

<h2>Who is this for?</h2>

<p>P1Xel Editor is made for:</p>

<ul>
  <li>Game Boy Color developers</li>
  <li>retro game developers</li>
  <li>pixel artists working with indexed palettes</li>
  <li>homebrew creators</li>
  <li>small engine/toolchain developers</li>
  <li>anyone making tiny 8×8 tile-based worlds</li>
</ul>

<h2>Simple, focused, useful</h2>

<p>
This is not a huge general-purpose art program. It is a focused production tool for tiny indexed tiles, sprites, palettes, and maps.
</p>

<p>
If you are building a Game Boy Color-style game, P1Xel Editor helps you create art and level data in one place.
</p>
