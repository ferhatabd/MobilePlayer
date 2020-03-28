//
//  File.swift
//  
//
//  Created by Ferhat Abdullahoglu on 25.03.2020.
//

import UIKit

/// Callback for playToggle button
public typealias PlayerToggleCallback = (() ->Void)
/// Action button callback
public typealias ActionSourceView = UIView
public typealias ActionButtonCallback = ((ActionSourceView) -> Void)
/// Close button callback
public typealias DismissButtonCallback = (() -> Void)
/// Skip fwd callback
public typealias SkipFwdCallback = (() -> Void)
/// Skip bwd callback
public typealias SkipBwdCallback = (() -> Void)

/// Lays out the rules for any view becoming eligible to be able to
/// used as an external media player controller view
public protocol MobilePlayerControllable where Self: UIView {
    
    var toggleCallback: PlayerToggleCallback? { get set }
    var actionButtonCallback: ActionButtonCallback? { get set }
    var dismissButtonCallback: DismissButtonCallback? { get set }
    var skipFwdCallback: SkipFwdCallback? { get set }
    var skipBwdCallback: SkipBwdCallback? { get set }
    
    var slider: Slider! { get set }

    /// Method to hide the controls view
    /// - Parameters:
    ///   - hidden: Hide flag
    ///   - animated: Animation flag
    ///
    func setControls(hidden: Bool, animated: Bool, _ completion: (() -> Void)?)
    
    /// Delivers the state change info
    /// - Parameter state: New state
    func playerStateDidChange(_ state: MobilePlayerViewController.State)
    
    func updateSlider(maxValue: Float, availableValue: Float, currentValue: Float)
    
    /// Updates the current time text
    /// - Parameter text: Current time string
    func currentTime(text: String)
    
    /// Updates the remaining time text
    /// - Parameter text: Remaining time string
    func remainingTime(text: String)
    
    /// Updates the duration text
    /// - Parameter text: Duration string
    func duration(text: String)
    
    /// Change the seeking status
    /// - Parameter isSeeking: New Seek status
    func setSeeking(_ isSeeking: Bool)
    
    /// Sets the Toggle action callback
    /// - Parameter callback: callback to be used
    func setToggleCallback(_ callback: @escaping PlayerToggleCallback) -> Void
    
    /// Sets the action callback
    /// - Parameter callback: callback to be used
    func setActionCallback(_ callback: @escaping ActionButtonCallback) -> Void
    
    /// Sets the Dismiss action callback
    /// - Parameter callback: callback to be used
    func setDismissCallback(_ callback: @escaping DismissButtonCallback) -> Void
    
    /// Sets the Skip fwd action callback
    /// - Parameter callback: callback to be used
    func setSkipFwdCallback(_ callback: @escaping SkipFwdCallback) -> Void
    
    /// Sets the Skip bwd action callback
    /// - Parameter callback: callback to be used
    func setSkipBwdCallback(_ callback: @escaping SkipBwdCallback) -> Void
    
    
}

