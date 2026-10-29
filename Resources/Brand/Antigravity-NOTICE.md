# Antigravity mark

`AntigravityDarkMark.svg` is the original `antigravity-gradient-logo.svg`
extracted from Google Antigravity IDE's `Contents/Resources/app/out/media`.
It identifies Google Antigravity; the logo and trademark belong to Google.

`../Images/AntigravityDarkMark.png` preserves the original colors and transparency.
It is rasterized because macOS's native SVG image renderer omits the filters
that produce this logo's multicolor gradient.

To regenerate with librsvg:

```sh
rsvg-convert --width 256 --height 256 \
  --output Resources/Images/AntigravityDarkMark.png \
  Resources/Brand/AntigravityDarkMark.svg
```
