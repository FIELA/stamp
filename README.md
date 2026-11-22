# 图章

「图章」是一款原生 macOS 图章编辑器，适用于运行 macOS 14 或更新版本的 Apple 芯片 Mac。

- 编辑圆章和方章，在朱文与阴文之间切换。
- 为每组文字单独选择字体和排版。支持横排、竖排、上下弧和从右到左的篆刻分列。
- 在印章库保存、切换和复制图章，也可导出或导入 JSON 备份。
- 导出 PNG、GIF、BMP、JPG 或 TIFF，复制到剪贴板，使用系统打印预览，或给已有图片盖章后另存。
- 支持 25%–400% 预览缩放、72–2400 DPI 和三档绘制质量。

## 构建

安装 Xcode Command Line Tools 后，在项目目录用以下命令构建并打开应用。

```sh
./build.sh
open "build/图章.app"
```

默认生成 arm64 应用。字体资源随应用打包，由应用在进程内加载。

## 字体

- [霞鹜篆书](https://github.com/lxgw/LxgwSeal)
- [敬峰中山王篆](https://github.com/SuperMate-Ai/JFZSKSealScript)
- [马善政毛笔楷书](https://github.com/googlefonts/mashanzheng)

各字体的 SIL Open Font License 1.1 随字体文件保存在 [Resources/Fonts](Resources/Fonts)。
