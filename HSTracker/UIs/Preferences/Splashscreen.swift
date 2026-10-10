/*
 * This file is part of the HSTracker package.
 * (c) Benjamin Michotte <bmichotte@gmail.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 *
 * Created on 13/02/16.
 */

import Cocoa

class Splashscreen: NSWindowController {
    @IBOutlet var information: NSTextField!
    @IBOutlet var progressBar: NSProgressIndicator!

    override func windowDidLoad() {
        super.windowDidLoad()
        guard let information, let progressBar, let contentView = window?.contentView else {
            return
        }
        information.alignment = .center
        information.textColor = NSColor(calibratedRed: 0.906, green: 0.788, blue: 0.863, alpha: 0.9)

        // The system bar follows the accent colour (blue by default); show a thin gold one instead.
        // progressBar stays as the hidden outlet that display() and RemoteConfig still drive.
        progressBar.isHidden = true
        let track = NSView(frame: NSRect(x: 95, y: 26, width: 160, height: 3))
        track.wantsLayer = true
        track.layer?.cornerRadius = 1.5
        track.layer?.masksToBounds = true
        track.layer?.backgroundColor = NSColor(white: 1, alpha: 0.18).cgColor
        let fill = CALayer()
        fill.frame = CGRect(x: 0, y: 0, width: 60, height: 3)
        fill.cornerRadius = 1.5
        fill.backgroundColor = NSColor(calibratedRed: 1, green: 0.784, blue: 0.31, alpha: 1).cgColor
        track.layer?.addSublayer(fill)
        contentView.addSubview(track)

        let slide = CABasicAnimation(keyPath: "position.x")
        slide.fromValue = -30
        slide.toValue = 190
        slide.duration = 1.6
        slide.repeatCount = .infinity
        slide.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        fill.add(slide, forKey: "slide")
    }

    func display(_ str: String, indeterminate: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let information, let progressBar else {
                return
            }
            information.stringValue = str
            progressBar.isIndeterminate = indeterminate
            progressBar.startAnimation(nil)
        }
    }
}
