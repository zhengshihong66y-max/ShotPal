import AppKit
import CoreText
import ImageIO
import UniformTypeIdentifiers
// Native renderer for the Chinese README graphics. Run on macOS:
// swift Tools/render_readme_chinese.swift <repository-root>
// Application footage is retained from the original exports; only the presentation copy is localized.
let root = URL(fileURLWithPath:CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let output = root.appendingPathComponent("docs/assets/github/zh-CN")
try FileManager.default.createDirectory(at:output.appendingPathComponent("posters"),withIntermediateDirectories:true)
func color(_ hex:Int)->NSColor { NSColor(srgbRed:CGFloat((hex>>16)&255)/255,green:CGFloat((hex>>8)&255)/255,blue:CGFloat(hex&255)/255,alpha:1) }
func drawText(_ s:String,_ r:NSRect,_ size:CGFloat,_ weight:NSFont.Weight = .semibold,_ tint:NSColor = color(0xf5f5f7),_ center:Bool = false) {
 let p=NSMutableParagraphStyle(); p.alignment=center ? .center : .left
 // SF Pro has no Han glyphs. Use an explicit CJK cascade with half-width
 // punctuation advances, instead of relying on the system UI font fallback.
 let suffix = weight == .regular ? "Regular" : "Semibold"
 let cjk = CTFontDescriptorCreateWithAttributes([
  kCTFontNameAttribute: "PingFangSC-" + suffix,
  kCTFontFeatureSettingsAttribute: [[kCTFontOpenTypeFeatureTag: "halt", kCTFontOpenTypeFeatureValue: 1]]
 ] as CFDictionary)
 let sf = CTFontDescriptorCreateWithAttributes([
  kCTFontNameAttribute: (size >= 24 ? "SFProDisplay-" : "SFProText-") + suffix,
  kCTFontCascadeListAttribute: [cjk]
 ] as CFDictionary)
 let font = CTFontCreateWithFontDescriptor(sf,size,nil)
 let text = NSMutableAttributedString(string:s,attributes:[.font:font,.foregroundColor:tint,.paragraphStyle:p])
 // Apply the CJK descriptor explicitly so punctuation retains its spacing feature.
 let chinese = CTFontCreateWithFontDescriptor(cjk,size,nil)
 let ns = s as NSString
 for i in 0..<ns.length {
  let u = ns.character(at:i)
  if (0x2E80...0x9FFF).contains(u) || (0xFF00...0xFFEF).contains(u) {
   text.addAttribute(.font,value:chinese,range:NSRange(location:i,length:1))
  }
 }
 if size >= 30 { text.addAttribute(.kern,value:-0.02*size,range:NSRange(location:0,length:text.length)) }
 text.draw(in:r)
}
func render(_ w:Int,_ h:Int,_ body:()->Void)->CGImage {
 let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:w,pixelsHigh:h,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
 NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:rep)
 let c=NSGraphicsContext.current!.cgContext;c.translateBy(x:0,y:CGFloat(h));c.scaleBy(x:1,y:-1);NSGraphicsContext.current=NSGraphicsContext(cgContext:c,flipped:true)
 body();NSGraphicsContext.restoreGraphicsState();return rep.cgImage!
}
func drawImage(_ image:CGImage,_ rect:NSRect) {
 NSImage(cgImage:image,size:NSSize(width:image.width,height:image.height)).draw(in:rect,from:.zero,operation:.copy,fraction:1,respectFlipped:true,hints:nil)
}
func png(_ image:CGImage,_ url:URL) {
 let dest=CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil)!;CGImageDestinationAddImage(dest,image,nil);CGImageDestinationFinalize(dest)
}
let posters:[(String,String,String,String)] = [
("download","粘贴链接，把影片带进来。","点击「+」，粘贴公开链接，再选择「下载」。","影片与来源信息，一起存入素材库。"),
("scene","一部影片，每个切点都清晰。","选择「分镜模式」，自动识别每一次镜头切换。","使用 ↑ / ↓，跳转到上一个或下一个切点。"),
("capture","留住你停下的那一帧。","选择「保存画面」（E），留下当前画面，","同时保留原片来源与准确时间码。"),
("audio","只取你需要的那段声音。","使用 I / O 设置入点与出点，","再按 P 导出所选音频片段。"),
("subtitle","本地转写，逐句同步。","选择「生成字幕」，在 Mac 上完成转写，","让每一句字幕都与影片播放保持同步。"),
("storyboard","你的分镜表，一步就绪。","选择「导出分镜表」，将镜号、时间码、画面与字幕，","整理成一份可直接使用的表格。"),
("drag","选好的素材，随手拖出去。","选中并拖动画面、音频或音乐，","直接放入你的剪辑软件。"),
("music","找到影片背后的音乐。","打开「音乐」标签页，识别影片中的曲目，","并定位它们在影片中出现的时刻。")]
for (key,title,a,b) in posters {
 let source=CGImageSourceCreateWithURL(root.appendingPathComponent("docs/assets/github/showcase/posters/\(key).webp") as CFURL,nil)!
 let original=CGImageSourceCreateImageAtIndex(source,0,nil)!
 let image=render(1440,1080) {
  drawImage(original,NSRect(x:0,y:0,width:1440,height:1080))
  NSColor.black.setFill();NSRect(x:0,y:0,width:1440,height:320).fill()
  drawText(title,NSRect(x:90,y:105,width:1260,height:94),64,.semibold,color(0xf5f5f7),true)
  drawText(a+"\n"+b,NSRect(x:140,y:237,width:1160,height:80),25,.semibold,color(0x86868b),true)
 }
 png(image,output.appendingPathComponent("posters/\(key).png"))
}
func smooth(_ value:Double)->Double {let t=min(1,max(0,value));return t*t*t*(t*(t*6-15)+10)}
func activity(_ index:Int,_ t:Double)->Double {
 if index==0 {if t<480{return smooth(t/480)};if t<2600{return 1};return 1-smooth((t-2600)/480)}
 if index==1 {if t<2600{return 0};if t<3080{return smooth((t-2600)/480)};if t<5000{return 1};return 1-smooth((t-5000)/480)}
 if t<480{return 1-smooth(t/480)};return smooth((t-5000)/480)
}
let src=CGImageSourceCreateWithURL(root.appendingPathComponent("docs/assets/github/shotpal-feature-trio-github.gif") as CFURL,nil)!
let count=CGImageSourceGetCount(src)
let dest=CGImageDestinationCreateWithURL(output.appendingPathComponent("shotpal-feature-trio-github.gif") as CFURL,UTType.gif.identifier as CFString,count,nil)!
CGImageDestinationSetProperties(dest,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFLoopCount:0]] as CFDictionary)
var elapsed=0.0
let labels=["01  导入","02  分析","03  输出"]
let titles=["把原片带进来。","看清每个选择。","带走所需灵感。"]
let descriptions=["粘贴公开链接，或导入本地影片。\n文件与来源信息，一起保存。","分镜、画面、声音、字幕与音乐，\n始终关联原片的同一条时间线。","将画面与片段整理进素材库，\n随时复用，为下一次剪辑做好准备。"]
let starts=[0x4b2c29,0x23433a,0x382f55],ends=[0x261c1d,0x192824,0x211e32]
for frame in 0..<count {
 let original=CGImageSourceCreateImageAtIndex(src,frame,nil)!
 let properties=CGImageSourceCopyPropertiesAtIndex(src,frame,nil)! as NSDictionary
 let gif=properties[kCGImagePropertyGIFDictionary] as! NSDictionary
 let delay=(gif[kCGImagePropertyGIFUnclampedDelayTime] ?? gif[kCGImagePropertyGIFDelayTime]) as! Double
 let image=render(1100,606) {
  NSGradient(starting:color(0x121214),ending:color(0x09090b))!.draw(in:NSRect(x:0,y:0,width:1100,height:606),angle:65)
  drawText("专为拉片而生，读懂每一部影片。",NSRect(x:60,y:43,width:980,height:69),43,.semibold,color(0xf5f5f7),true)
  for i in 0..<3 {
   let a=activity(i,elapsed), scale=1+0.022*a
   let w=(1056-2*14.663)/3, h=423.5
   let x=22+Double(i)*(w+14.663)-(w*(scale-1))/2
   let y=606-29.337-9.02*a-h*scale
   let card=NSRect(x:x,y:y,width:w*scale,height:h*scale)
   let shape=NSBezierPath(roundedRect:card,xRadius:23.84,yRadius:23.84)
   NSGradient(colorsAndLocations:(color(starts[i]),0),(color(ends[i]),0.62),(color(0x141416),1))!.draw(in:shape,angle:65)
   if a>0 {NSColor.white.withAlphaComponent(0.26*a).setStroke();shape.lineWidth=1;shape.stroke()}
   // Retain the original animated application view, including footage and pointer movement.
   let ui=NSRect(x:x+14.663*scale,y:y+14.663*scale,width:(w-29.326)*scale,height:196.163*scale)
   NSGraphicsContext.saveGraphicsState();NSBezierPath(roundedRect:ui,xRadius:14.66,yRadius:14.66).addClip()
   drawImage(original,NSRect(x:0,y:0,width:1100,height:606));NSGraphicsContext.restoreGraphicsState()
   let tx=x+14.663*scale,tw=(w-29.326)*scale
   drawText(labels[i],NSRect(x:tx,y:y+238*scale,width:tw,height:25),14*scale,.semibold,color(0xb0b0b5))
   drawText(titles[i],NSRect(x:tx,y:y+268*scale,width:tw,height:51),34*scale)
   drawText(descriptions[i],NSRect(x:tx,y:y+326*scale,width:tw,height:78),18*scale,.regular,color(0xb7b7bd))
  }
 }
 CGImageDestinationAddImage(dest,image,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFDelayTime:delay,kCGImagePropertyGIFUnclampedDelayTime:delay]] as CFDictionary)
 elapsed += delay*1000
}
assert(CGImageDestinationFinalize(dest));print("Rendered 8 posters and \(count) animated frames, duration \(elapsed) ms")

var strip = try String(contentsOf:root.appendingPathComponent("docs/assets/github/release-strip.svg"),encoding:.utf8)
for (en,zh) in [("Version 1.2.1","版本 1.2.1"),("REQUIRES","系统要求"),("PROCESSOR","处理器"),("Apple silicon","Apple 芯片"),("DOWNLOAD","下载大小"),("Download DMG","下载 DMG")] {strip=strip.replacingOccurrences(of:en,with:zh)}
try strip.write(to:output.appendingPathComponent("release-strip.svg"),atomically:true,encoding:.utf8)
