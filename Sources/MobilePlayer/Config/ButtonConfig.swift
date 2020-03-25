//
//  ButtonConfig.swift
//  MobilePlayer
//
//  Created by Baris Sencan on 9/16/15.
//  Copyright (c) 2015 MovieLaLa. All rights reserved.
//

import UIKit

/// Holds button configuration values.
public class ButtonConfig: ElementConfig {
    
    /// Button height. Default value is 40.
    public let height: CGFloat
    
    /// Button image.
    public let image: UIImage?
    
    /// Button tint color. Default value is white.
    public let tintColor: UIColor
    
    /// Initializes using default values.
    public convenience init() {
        self.init(dictionary: [String: Any]())
    }
    
    /// Initializes using a dictionary.
    ///
    /// * Key for `height` is `"height"` and its value should be a number.
    /// * Key for `image` is `"image"` and its value should be an image asset name.
    /// * Key for `tintColor` is `"tintColor"` and its value should be a color hex string.
    ///
    /// - parameters:
    ///   - dictionary: Button configuration dictionary.
    public override init(dictionary: [String: Any]) {
        // Values need to be AnyObject for type conversions to work correctly.
        let dictionary = dictionary as [String: AnyObject]
        
        height = (dictionary["height"] as? CGFloat) ?? 40
        
        if let imageName = dictionary["image"] as? String {
            image = UIImage(named: imageName)
        } else if let identifier = dictionary["identifier"] as? String {
            switch identifier {
            case "close":
                image = UIImage(podResourceNamed: "MLCloseButton.png")?.template
            case "action":
                image = UIImage(podResourceNamed: "MLShareButton")?.template
            case "cast":
                image = nil
            case "airplay":
                image = nil
            case "skipForward":
                image = UIImage(podResourceNamed: "pbr_skip_fwd")?.template
            case "skipBackward":
                image = UIImage(podResourceNamed: "pbr_skip_bwd")?.template
            default:
                image = nil
            }
        } else {
            image = nil
        }
        
        if let tintColorHex = dictionary["tintColor"] as? String {
            tintColor = UIColor(hex: tintColorHex)
        } else {
            tintColor = UIColor.white
        }
        
        super.init(dictionary: dictionary)
    }
}
