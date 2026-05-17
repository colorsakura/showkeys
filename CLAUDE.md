# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 设计风格

- 遵循 Apple Design 设计语言：简洁、克制、圆润、轻量，优先使用清晰的层次、柔和的高光和低对比阴影。
- 默认主题采用 glassmorphism / Apple 风格玻璃质感：半透明渐变、细边框、高光层和轻微底部阴影，避免厚重拟物或高饱和装饰。
- SVG 图标统一为 24x24：使用 `viewBox="0 0 24 24"`，并显式声明 `width="24" height="24"`。
- 图标以线性符号为主：主线条使用 `#f5f5f7`，`fill="none"`，`stroke-linecap="round"`，`stroke-linejoin="round"`。
- 图标线宽保持一致：常规图标主 stroke 约 `1.9`，强调元素可略粗，辅助元素使用较低透明度（如 `opacity="0.55"` 或 `0.38`）。
- 同一组图标应保持统一的视觉重量、留白、圆角和居中构图；不要混用明显不同的图标风格。
- keycap 背景 SVG 应与图标配套：圆角玻璃面板、柔和高光、细 rim 边框，保证文字和特殊键图标在深色/半透明背景上有足够可读性。