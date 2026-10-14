import AppKit
let pb = NSPasteboard.general
let path = CommandLine.arguments[2]
let action = CommandLine.arguments[1]
if action == "save" {
    let items = (pb.pasteboardItems ?? []).map { item in
        Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type.rawValue, $0) } })
    }
    let data = try PropertyListSerialization.data(fromPropertyList: items, format: .binary, options: 0)
    try data.write(to: URL(fileURLWithPath: path))
} else if action == "image" || action == "tiff" {
    let image = NSImage(size: NSSize(width: 2, height: 2))
    image.lockFocus(); NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 2, height: 2).fill(); image.unlockFocus()
    if action == "tiff" {
        pb.clearContents(); pb.writeObjects([image])
        exit(0)
    }
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    let png = rep.representation(using: .png, properties: [:])!
    pb.clearContents(); pb.setData(png, forType: .png)
} else {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let saved = try PropertyListSerialization.propertyList(from: data, format: nil) as! [[String: Data]]
    let items = saved.map { values in
        let item = NSPasteboardItem()
        for (type, data) in values { item.setData(data, forType: NSPasteboard.PasteboardType(type)) }
        return item
    }
    pb.clearContents(); pb.writeObjects(items)
}
