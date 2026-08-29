/*
 * This file is part of the HSTracker package.
 * (c) Benjamin Michotte <bmichotte@gmail.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 *
 * Created on 16/02/16.
 */

import AppKit
import Foundation
import HearthMirror
import ImageIO

struct ImageUtils {
    enum ImageType: Int {
        case tile, art, cardArt, cardArtBG, hero
    }
    
    static func tileUrl(cardId: String) -> String {
        return "https://art.hearthstonejson.com/v1/tiles/\(cardId).png"
    }
    
    static func artUrl(cardId: String, lang: String) -> String {
        return "https://art.hearthstonejson.com/v1/render/latest/\(lang)/256x/\(cardId).png"
    }

    static func artUrlBG(cardId: String, lang: String) -> String {
        return "https://art.hearthstonejson.com/v1/bgs/latest/\(lang)/256x/\(cardId).png"
    }

    static func artUrl256(cardId: String) -> String {
        return "https://art.hearthstonejson.com/v1/256x/\(cardId).jpg"
    }

    // Full-body hero portrait, the URL HDT's heroImageDownloader uses.
    static func heroUrl(cardId: String) -> String {
        return "https://art.hearthstonejson.com/v1/heroes/latest/256x/\(cardId).png"
    }

    private static let cacheCapacity = 256
    private static var cache = SynchronizedLRUCache<String, NSImage>(capacity: cacheCapacity)
    private static var cacheArt = SynchronizedLRUCache<String, NSImage>(capacity: cacheCapacity)
    private static var cacheCardArt = SynchronizedLRUCache<String, NSImage>(capacity: cacheCapacity)
    private static var cacheCardArtBG = SynchronizedLRUCache<String, NSImage>(capacity: cacheCapacity)
    private static var cacheHero = SynchronizedLRUCache<String, NSImage>(capacity: cacheCapacity)
    private static let imageLoadQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "net.hearthsim.hstracker.image-loading"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 4
        return queue
    }()
    
    static func clearCache() {
        cache.removeAll()
        cacheArt.removeAll()
        cacheCardArt.removeAll()
        cacheCardArtBG.removeAll()
        cacheHero.removeAll()
        
        clearDirectory(path: Paths.cards)
        clearDirectory(path: Paths.cardsBG)
        clearDirectory(path: Paths.arts)
        clearDirectory(path: Paths.tiles)
        clearDirectory(path: Paths.heroes)
    }
    
    static func clearDirectory(path: URL) {
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: path,
                                                                       includingPropertiesForKeys: nil,
                                                                       options: .skipsHiddenFiles)
            for fileURL in fileURLs {
                try FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            logger.error(error)
        }
    }

    static func cachedTile(cardId: String) -> NSImage? {
        return cache[cardId]
    }

    // Completion handlers are always delivered on the main queue. Cache hits
    // requested on the main thread may complete synchronously; cache misses
    // always load in the background.
    
    static func tile(for cardId: String,
                     completion: @escaping ((NSImage?) -> Void)) {
        let image = cache[cardId]
        
        if let image = image {
            completeOnMain(image, completion: completion)
            return
        }
		
        loadImage(type: .tile, cardId: cardId, completion: completion)
    }
    
    static func art(for cardId: String, completion: @escaping ((NSImage?) -> Void)) {
        let image = cacheArt[cardId]
        
        if let image = image {
            completeOnMain(image, completion: completion)
            return
        }
        loadImage(type: .art, cardId: cardId, completion: completion)
    }
    
    static func cardArt(for cardId: String, completion: @escaping ((NSImage?) -> Void)) {
        let image = cacheCardArt[cardId]
        
        if let image = image {
            completeOnMain(image, completion: completion)
            return
        }
        loadImage(type: .cardArt, cardId: cardId, completion: completion)
    }
    
    static func cardArtBG(for cardId: String, baconTriple: Bool, completion: @escaping ((NSImage?) -> Void)) {
        let finalCardId = "\(cardId)\(baconTriple ? "_triple" : "")"
        let image = cacheCardArtBG[finalCardId]
        
        if let image = image {
            completeOnMain(image, completion: completion)
            return
        }
        loadImage(type: .cardArtBG, cardId: finalCardId, completion: completion)
    }

    static func cachedHero(cardId: String) -> NSImage? {
        return cacheHero[cardId]
    }

    static func hero(for cardId: String, completion: @escaping ((NSImage?) -> Void)) {
        if let image = cacheHero[cardId] {
            completeOnMain(image, completion: completion)
            return
        }
        loadImage(type: .hero, cardId: cardId, completion: completion)
    }

    static func cachedArt(cardId: String) -> NSImage? {
        let res = cacheArt[cardId]
        
        return res
    }
    
    private static func loadImage(type: ImageType, cardId: String, completion: @escaping ((NSImage?) -> Void)) {
        // Check if the image has been downloaded
        var path: URL
        switch type {
        case .tile:
            path = Paths.tiles.appendingPathComponent("\(cardId).jpg")
        case .art:
            path = Paths.arts.appendingPathComponent("\(cardId).jpg")
        case .cardArt:
            path = Paths.cards.appendingPathComponent("\(cardId).jpg")
        case .cardArtBG:
            path = Paths.cardsBG.appendingPathComponent("\(cardId).jpg")
        case .hero:
            path = Paths.heroes.appendingPathComponent("\(cardId).png")
        }
        imageLoadQueue.addOperation {
            if let image = decodedImage(contentsOf: path) {
                switch type {
                case .tile:
                    cache[cardId] = image
                case .art:
                    cacheArt[cardId] = image
                case .cardArt:
                    cacheCardArt[cardId] = image
                case .cardArtBG:
                    cacheCardArtBG[cardId] = image
                case .hero:
                    cacheHero[cardId] = image
                }

                completeOnMain(image, completion: completion)
                return
            }
            if FileManager.default.fileExists(atPath: path.path) {
                logger.error("failed to decode cached image at \(path)")
            }

            // Download image
            let url: String
            switch type {
            case .tile:
                url = tileUrl(cardId: cardId)
            case .art:
                url = artUrl256(cardId: cardId)
            case .cardArt:
                url = artUrl(cardId: cardId, lang: Settings.hearthstoneLanguage?.rawValue ?? "enUS")
            case .cardArtBG:
                url = artUrlBG(cardId: cardId, lang: Settings.hearthstoneLanguage?.rawValue ?? "enUS")
            case .hero:
                url = heroUrl(cardId: cardId)
            }
            guard let url = URL(string: url) else {
                logger.error("invalid image URL \(url)")
                completeOnMain(nil, completion: completion)
                return
            }
            logger.verbose("downloading \(type) \(url) to \(path)")

            URLSession.shared.dataTask(with: url) { data, _, error in
                if let error = error {
                    logger.error("download error \(error)")
                    completeOnMain(nil, completion: completion)
                    return
                }
                guard let data else {
                    logger.error("download returned no data for \(url)")
                    completeOnMain(nil, completion: completion)
                    return
                }
                imageLoadQueue.addOperation {
                    guard let image = decodedImage(data: data) else {
                        logger.error("download returned an invalid image for \(url)")
                        completeOnMain(nil, completion: completion)
                        return
                    }
                    do {
                        try data.write(to: path, options: [.atomic])
                    } catch {
                        logger.error("failed to cache image at \(path): \(error)")
                    }

                    switch type {
                    case .tile:
                        cache[cardId] = image
                    case .art:
                        cacheArt[cardId] = image
                    case .cardArt:
                        cacheCardArt[cardId] = image
                    case .cardArtBG:
                        cacheCardArtBG[cardId] = image
                    case .hero:
                        cacheHero[cardId] = image
                    }

                    completeOnMain(image, completion: completion)
                }
            }.resume()
        }
    }

    private static func decodedImage(contentsOf url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        return decodedImage(source: source)
    }

    private static func decodedImage(data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return decodedImage(source: source)
    }

    private static func decodedImage(source: CGImageSource) -> NSImage? {
        let options = [
            kCGImageSourceShouldCache: true,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, options) else {
            return nil
        }
        return NSImage(cgImage: image, size: NSSize(width: CGFloat(image.width), height: CGFloat(image.height)))
    }

    private static func completeOnMain(_ image: NSImage?, completion: @escaping ((NSImage?) -> Void)) {
        if Thread.isMainThread {
            completion(image)
        } else {
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }
}
