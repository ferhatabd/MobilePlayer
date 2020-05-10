//
//  MobilePlayerViewController.swift
//  MobilePlayer
//
//  Created by Baris Sencan on 12/02/15.
//  Copyright (c) 2015 MovieLaLa. All rights reserved.
//

import UIKit
import AVKit



/// A view controller for playing media content.
open class MobilePlayerViewController: UIViewController {
    // MARK: Playback State
    
    /// Playback state.
    public enum State {
        
        /// Either playback has not started or playback was stopped due to a `stop()` call or an error. When an error
        /// occurs, a corresponding `MobilePlayerDidEncounterErrorNotification` notification is posted.
        case idle
        
        /// The video will start playing, but sufficient data to start playback has to be loaded first.
        case buffering
        
        /// The video is currently playing.
        case playing
        
        /// The video is currently paused.
        case paused
    }
    
    /// The previous value of `state`. Default is `.Idle`.
    public private(set) var previousState: State = .idle
    
    /// Current `State` of the player. Default is `.Idle`.
    public private(set) var state: State = .idle {
        didSet {
            previousState = oldValue
        }
    }
    
    // MARK: Player Configuration
    
    // TODO: Move inside MobilePlayerConfig
    public static let playbackInterfaceUpdateInterval = 0.25
    
    /// The global player configuration object that is loaded by a player if none is passed for its
    /// initialization.
    public static let globalConfig = MobilePlayerConfig()
    
    /// The configuration object that was used to initialize the player, may point to the global player configuration
    /// object.
    public var config: MobilePlayerConfig!
    
    /// Player
    public var moviePlayer: AVPlayer! { playerView?.player }
    
    
    // MARK: Mapped Properties
    
    /// A localized string that represents the video this controller manages. Setting a value will update the title label
    /// in the user interface if one exists.
    open override var title: String? {
        didSet {
            guard let titleLabel = getViewForElementWithIdentifier("title") as? Label else { return}
            titleLabel.text = title
            titleLabel.superview?.setNeedsLayout()
        }
    }
    
    #if os(iOS)
    open override var prefersStatusBarHidden: Bool { true }
    #endif
    
    #if os(iOS)
    open override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .fade }
    #endif
    
    #if os(iOS)
    open override var prefersHomeIndicatorAutoHidden: Bool { true }
    #endif
    
    /// Bundle url to check for the resources
    ///
    /// If it's left nil, then the bundle for the __MobilePlayer__ package
    /// will be used to look for the resources
    open class var bundleForResources: URL? { nil }
    
    // MARK: Private Properties
    private var controlsView: MobilePlayerControlsView!
    private var previousStatusBarHiddenValue: Bool?
    @available(tvOS, unavailable)
    private var previousStatusBarStyle: UIStatusBarStyle!
    private var isFirstPlay = true
    fileprivate var seeking = false {
        didSet {
            externalControlsView?.setSeeking(seeking)
        }
    }
    fileprivate var wasPlayingBeforeSeek = false
    private var hideControlsTimer: Timer?
    private var contentUrl: URL!
    private var playerView: PlayerView!
    private var playerObserver: Any!
    private var externalControlsView: MobilePlayerControllable!
    private var didUserTap = false
    
    // MARK: Initialization
   
    /// initialize the main player VC
    private func initializeMobilePlayerViewController() {
        view.clipsToBounds = true
        edgesForExtendedLayout = []
        initializePlayerView()
        self.playerView.url = self.contentUrl
        playerView.playerLayer.videoGravity = .resizeAspect
        initializeControlsView()
        parseContentURLIfNeeded()
        if let watermarkConfig = config.watermarkConfig {
            showOverlayViewController(WatermarkViewController(config: watermarkConfig))
        }
    }
    
    private func initializePlayerView() {
        playerView?.removeFromSuperview()
        playerView = PlayerView()
        playerView.translatesAutoresizingMaskIntoConstraints = false
        playerView.delegate = self
        view.insertSubview(playerView, at: 0)
        
        playerView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        playerView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        playerView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        playerView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        
    }
    
    private func dismissCallback() {
        if let navigationController = navigationController {
            navigationController.popViewController(animated: true)
        } else if let presentingController = presentingViewController {
            presentingController.dismiss(animated: true)
        }
    }
    
    #if os(iOS)
    private func actionButtonCallback(sourceView: UIView) {
        resetHideControlsTimer()
        showContentActions(sourceView: sourceView)
    }
    #endif
    
    private func toggleButtonCallback() {
        resetHideControlsTimer()
        state == .playing ? pause() : play()
    }
    
    private func initializeControlsView() {
        (getViewForElementWithIdentifier("playback") as? Slider)?.delegate = self
        
        (getViewForElementWithIdentifier("close") as? Button)?.addCallback(
            callback: { [weak self] in
                self?.dismissCallback()
            },
            forControlEvents: .touchUpInside)
        
        #if os(iOS)
        if let actionButton = getViewForElementWithIdentifier("action") as? Button {
            actionButton.isHidden = true // Initially hidden until 1 or more `activityItems` are set.
            actionButton.addCallback(
                callback: { [weak self] in
                    guard let slf = self else {
                        return
                    }
                    slf.actionButtonCallback(sourceView: actionButton)
                },
                forControlEvents: .touchUpInside)
        }
        #endif
        
        
        (getViewForElementWithIdentifier("play") as? ToggleButton)?.addCallback(
            callback: { [weak self] in
                self?.toggleButtonCallback()
            },
            forControlEvents: .touchUpInside)
        
        initializeControlsViewTapRecognizers()
        
        controlsView.translatesAutoresizingMaskIntoConstraints = false
    }
    
    private func initializeControlsViewTapRecognizers() {
        let singleTapRecognizer = UITapGestureRecognizer { [weak self] in self?.handleContentTap() }
        singleTapRecognizer.numberOfTapsRequired = 1
        controlsView.addGestureRecognizer(singleTapRecognizer)
        let doubleTapRecognizer = UITapGestureRecognizer { [weak self] in self?.handleContentDoubleTap() }
        doubleTapRecognizer.numberOfTapsRequired = 2
        controlsView.addGestureRecognizer(doubleTapRecognizer)
        singleTapRecognizer.require(toFail: doubleTapRecognizer)
    }
    
    // MARK: View Controller Lifecycle
    
    /// Called after the controller's view is loaded into memory.
    ///
    /// This method is called after the view controller has loaded its view hierarchy into memory. This method is
    /// called regardless of whether the view hierarchy was loaded from a nib file or created programmatically in the
    /// `loadView` method. You usually override this method to perform additional initialization on views that were
    /// loaded from nib files.
    ///
    /// If you override this method make sure you call super's implementation.
    open override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .black
        
        if let prerollViewController = prerollViewController {
            shouldAutoplay = false
            showOverlayViewController(prerollViewController)
        }
    }
    
    /// Called to notify the view controller that its view is about to layout its subviews.
    ///
    /// When a view's bounds change, the view adjusts the position of its subviews. Your view controller can override
    /// this method to make changes before the view lays out its subviews.
    ///
    /// The default implementation of this method sets the frame of the controls view.
    open override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        //        controlsView.frame = view.bounds
    }
    
    /// Notifies the view controller that its view is about to be added to a view hierarchy.
    ///
    /// If `true`, the view is being added to the window using an animation.
    ///
    /// The default implementation of this method hides the status bar.
    ///
    /// - parameters:
    ///  - animated: If `true`, the view is being added to the window using an animation.
    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Force hide status bar.
        #if os(iOS)
        setNeedsStatusBarAppearanceUpdate()
        #endif
        resetHideControlsTimer()
    }
    
    /// Notifies the view controller that its view is about to be removed from a view hierarchy.
    ///
    /// If `true`, the disappearance of the view is being animated.
    ///
    /// The default implementation of this method stops playback and restores status bar appearance to how it was before
    /// the view appeared.
    ///
    /// - parameters:
    ///  - animated: If `true`, the disappearance of the view is being animated.
    open override func viewWillDisappear(_ animated: Bool) {
        
        super.viewWillDisappear(animated)
        if moviePlayer.rate > 0 {
            stop()
        }
    }
    
    // MARK: Deinitialization
    
    deinit {
        hideControlsTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        if let token = self.playerObserver {
            moviePlayer?.removeTimeObserver(token)
            playerObserver = nil
        }
    }
    
    // MARK: Playback
    
    /// Indicates whether content should begin playback automatically.
    ///
    /// The default value of this property is true. This property determines whether the playback of network-based
    /// content begins automatically when there is enough buffered data to ensure uninterrupted playback.
    public var shouldAutoplay: Bool = true
    
    /// Player will start playing from the beginning once it reaches the end
    public var shouldAutoRepeat: Bool = false
    
    /// Initializes a player with content given by `contentURL`. If provided, the overlay view controllers used to
    /// initialize the player should be different instances from each other.
    ///
    /// - parameters:
    ///   - contentURL: URL of the content that will be used for playback.
    ///   - config: Player configuration. Defaults to `globalConfig`.
    ///   - prerollViewController: Pre-roll view controller. Defaults to `nil`.
    ///   - pauseOverlayViewController: Pause overlay view controller. Defaults to `nil`.
    ///   - postrollViewController: Post-roll view controller. Defaults to `nil`.
    public func setConfig(contentURL: URL,
                          config: MobilePlayerConfig = MobilePlayerViewController.globalConfig,
                          prerollViewController: MobilePlayerOverlayViewController? = nil,
                          pauseOverlayViewController: MobilePlayerOverlayViewController? = nil,
                          postrollViewController: MobilePlayerOverlayViewController? = nil,
                          externalControlsView view: MobilePlayerControllable? = nil) {
        self.config = config
        self.prerollViewController = prerollViewController
        self.pauseOverlayViewController = pauseOverlayViewController
        self.postrollViewController = postrollViewController
        self.contentUrl = contentURL
        self.externalControlsView = view
        setControlsView()
        initializeMobilePlayerViewController()
        controlsHidden = true 
    }
    
    private func wireExternalView() {
        guard let externalControls = self.externalControlsView else { return }
        controlsView?.setExternalView(externalControls)
        
        /// set external view callbacks
        externalControls.setToggleCallback { [weak self] in
            self?.toggleButtonCallback()
        }
        #if os(iOS)
        externalControls.setActionCallback { [weak self] (sourceView) in
            self?.actionButtonCallback(sourceView: sourceView)
        }
        #endif
        externalControls.setDismissCallback { [weak self] in
            self?.dismissCallback()
        }
        externalControls.setSkipBwdCallback { [weak self] in
            self?.skipBwd()
        }
        externalControls.setSkipFwdCallback { [weak self] in
            self?.skipFwd()
        }
    }
    
    private func setControlsView() {
        controlsView?.removeFromSuperview()
        
        controlsView = MobilePlayerControlsView(config: config)
        controlsView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controlsView)
        
//        if #available(iOS 11.0, *) {
//            controlsView.topAnchor.constraint(equalTo: topLayoutGuide.bottomAnchor).isActive = true
//            controlsView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor).isActive = true
//        } else {
//            controlsView.topAnchor.constraint(equalTo: topLayoutGuide.bottomAnchor).isActive = true
//        }
        controlsView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        controlsView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        controlsView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        controlsView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        
        wireExternalView()
    }
    
    /// Initiates playback of current content.
    ///
    /// Starting playback causes dismiss to be called on prerollViewController, pauseOverlayViewController
    /// and postrollViewController.
    open func play() {
        moviePlayer?.play()
    }
    
    /// Pauses playback of current content.
    ///
    /// Pausing playback causes pauseOverlayViewController to be shown.
    open func pause() {
        moviePlayer?.pause()
    }
    
    /// Ends playback of current content.
    open func stop() {
        moviePlayer?.pause()
    }
    
    /// Scrolls playback to 15 seconds later
    open func skipFwd() {
        guard let player = moviePlayer, let item = player.currentItem else { return }
        let currentTime = player.currentTime().seconds
        let nextTime = min(currentTime + 15, item.duration.seconds)
        player.seek(to: CMTime(seconds: nextTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC)))
        resetHideControlsTimer()
    }
    
    /// Scrolls playback to 15 seconds before
    open func skipBwd() {
        guard let player = moviePlayer else { return }
        let currentTime = player.currentTime().seconds
        let nextTime = max(currentTime - 15, 0)
        player.seek(to: CMTime(seconds: nextTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC)))
        resetHideControlsTimer()
    }
    
    
    // MARK: Video Rendering
    
    /// Makes playback content fit into player's view.
    public func fitVideo() {
        playerView.playerLayer.videoGravity = .resizeAspect
    }
    
    /// Makes playback content fill player's view.
    public func fillVideo() {
        playerView.playerLayer.videoGravity = .resizeAspectFill
    }
    
    /// Makes playback content switch between fill/fit modes when content area is double tapped. Overriding this method
    /// is recommended if you want to change this behavior.
    public func handleContentDoubleTap() {
        // TODO: videoScalingMode property and enum.
        playerView.playerLayer.videoGravity != .resizeAspectFill ? fillVideo() : fitVideo()
    }
    
    // MARK: Social
    
    /// An array of activity items that will be used for presenting a `UIActivityViewController` when the action
    /// button is pressed (if it exists). If content is playing, it is paused automatically at presentation and will
    /// continue after the controller is dismissed. Override `showContentActions()` if you want to change the button's
    /// behavior.
    public var activityItems: [Any]? {
        didSet {
            let isEmpty = activityItems?.isEmpty ?? true
            getViewForElementWithIdentifier("action")?.isHidden = isEmpty
        }
    }
    
    /// An array of activity types that will be excluded when presenting a `UIActivityViewController`
    #if os(iOS)
    public var excludedActivityTypes: [UIActivity.ActivityType]? = [
        .assignToContact,
        .saveToCameraRoll,
        .postToVimeo,
        .airDrop
    ]
    #endif
    
    /// Method that is called when a control interface button with identifier "action" is tapped. Presents a
    /// `UIActivityViewController` with `activityItems` set as its activity items. If content is playing, it is paused
    /// automatically at presentation and will continue after the controller is dismissed. Overriding this method is
    /// recommended if you want to change this behavior.
    ///
    /// parameters:
    ///   - sourceView: On iPads the activity view controller is presented as a popover and a source view needs to
    ///     provided or a crash will occur.
    #if os(iOS)
    open func showContentActions(sourceView: UIView? = nil) {
        guard let activityItems = activityItems, !activityItems.isEmpty else { return }
        let wasPlaying = (state == .playing)
        moviePlayer.pause()
        let activityVC = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        activityVC.excludedActivityTypes =  excludedActivityTypes
        activityVC.completionWithItemsHandler = { activityType, completed, returnedItems, activityError in
            if wasPlaying {
                self.moviePlayer.play()
            }
        }
        if let sourceView = sourceView {
            activityVC.popoverPresentationController?.sourceView = controlsView
            activityVC.popoverPresentationController?.sourceRect = sourceView.convert(
                sourceView.bounds,
                to: controlsView)
        }
        present(activityVC, animated: true, completion: nil)
    }
    #endif
    
    // MARK: Controls
    
    /// Indicates if player controls are hidden. Setting its value will animate controls in or out.
    public var controlsHidden: Bool {
        get {
            return controlsView.controlsHidden
        }
        set {
            newValue ? hideControlsTimer?.invalidate() : resetHideControlsTimer()
            controlsView.controlsHidden = newValue
        }
    }
    
    /// Returns the view associated with given player control element identifier.
    ///
    /// - parameters:
    ///   - identifier: Element identifier.
    /// - returns: View or nil if element is not found.
    public func getViewForElementWithIdentifier(_ identifier: String) -> UIView? {
        if let view = controlsView.topBar.getViewForElementWithIdentifier(identifier: identifier) {
            return view
        }
        return controlsView.bottomBar.getViewForElementWithIdentifier(identifier: identifier)
    }
    
    /// Hides/shows controls when content area is tapped once. Overriding this method is recommended if you want to change
    /// this behavior.
    public func handleContentTap() {
        didUserTap = true
        controlsHidden = !controlsHidden
        externalControlsView?.setControls(hidden: controlsHidden, animated: true, nil)
    }
    
    // MARK: Overlays
    
    private var timedOverlays = [TimedOverlayInfo]()
    
    /// The `MobilePlayerOverlayViewController` that will be presented on top of the player content at start. If a
    /// controller is set then content will not start playing automatically even if `shouldAutoplay` is `true`. The
    /// controller will dismiss if user presses the play button or `play()` is called.
    public var prerollViewController: MobilePlayerOverlayViewController?
    
    /// The `MobilePlayerOverlayViewController` that will be presented on top of the player content whenever playback is
    /// paused. Does not include pauses in playback due to buffering.
    public var pauseOverlayViewController: MobilePlayerOverlayViewController?
    
    /// The `MobilePlayerOverlayViewController` that will be presented on top of the player content when playback
    /// finishes.
    public var postrollViewController: MobilePlayerOverlayViewController?
    
    /// Presents given overlay view controller on top of the player content immediately, or at a given content time for
    /// a given duration. Both starting time and duration parameters should be provided to show a timed overlay.
    ///
    /// - parameters:
    ///   - overlayViewController: The `MobilePlayerOverlayViewController` to be presented.
    ///   - startingAtTime: Content time the overlay will be presented at.
    ///   - forDuration: Added on top of `startingAtTime` to calculate the content time when overlay will be dismissed.
    public func showOverlayViewController(_ overlayViewController: MobilePlayerOverlayViewController,
                                          startingAtTime presentationTime: TimeInterval? = nil,
                                          forDuration showDuration: TimeInterval? = nil) {
        if let presentationTime = presentationTime, let showDuration = showDuration {
            timedOverlays.append(TimedOverlayInfo(
                startTime: presentationTime,
                duration: showDuration,
                overlay: overlayViewController))
        } else if overlayViewController.parent == nil {
            overlayViewController.delegate = self
            addChild(overlayViewController)
            overlayViewController.view.clipsToBounds = true
            overlayViewController.view.frame = controlsView.overlayContainerView.bounds
            controlsView.overlayContainerView.addSubview(overlayViewController.view)
            overlayViewController.didMove(toParent: self)
        }
    }
    
    /// Can be used as the last point before the postrol view controller shown in ortder to update it
    /// - Parameter viewController: PostrollViewController to be shown
    open func willShowPostrollViewController(_ viewController: MobilePlayerOverlayViewController) { }
    
    /// Dismisses all currently presented overlay view controllers and clears any timed overlays.
    public func clearOverlays() {
        for timedOverlayInfo in timedOverlays {
            timedOverlayInfo.overlay.dismiss()
        }
        timedOverlays.removeAll()
        for childViewController in children {
            if childViewController is WatermarkViewController { continue }
            (childViewController as? MobilePlayerOverlayViewController)?.dismiss()
        }
    }
    
    /// Player is ready to play
    open func readyToPlay()  {
        // start if autoPlay is active
        if shouldAutoplay {
            self.play()
        }
    }
    
    
    /// Conveys the state change information to anyone listenining
    ///
    /// Default implementation of this methos does nothing, it's meant to be
    /// overriden by subclasses those that need to
    ///
    /// - Parameters:
    ///   - from: Old state
    ///   - to: New state
    open func playerStateChanged(from: State, to: State) {}
    
    
    // MARK: Private Methods
    
    private func parseContentURLIfNeeded() {
        guard let youtubeID = YoutubeParser.youtubeIDFromURL(url: self.contentUrl) else { return }
        YoutubeParser.h264videosWithYoutubeID(youtubeID) { videoInfo, error in
            if let error = error {
                NotificationCenter.default.post(name: NSNotification.Name(rawValue: MobilePlayerDidEncounterErrorNotification), object: self, userInfo: [MobilePlayerErrorUserInfoKey: error])
            }
            guard let videoInfo = videoInfo else { return }
            self.title = self.title ?? videoInfo.title
            if
                let previewImageURLString = videoInfo.previewImageURL,
                let previewImageURL = URL(string: previewImageURLString) {
                URLSession.shared.dataTask(with: previewImageURL) { data, response, error in
                    guard let data = data else { return }
                    DispatchQueue.main.async {
                        self.controlsView.previewImageView.image = UIImage(data: data)
                    }
                }
            }
            if let videoURL = videoInfo.videoURL {
                self.contentUrl = URL(string: videoURL)
            }
        }
    }
    
    private func doFirstPlaySetupIfNeeded() {
        if isFirstPlay {
            isFirstPlay = false
            controlsHidden = true
            controlsView.previewImageView.isHidden = true
            controlsView.activityIndicatorView.stopAnimating()
        }
    }
    
    private func updatePlaybackInterface() {
        
        guard let item = moviePlayer?.currentItem else { return }
        let isTimeValid = item.duration.isNumeric && item.duration.isValid
        
        let maxValue = Float(isTimeValid ? item.duration.seconds : 0)
        let availableValue = Float(isTimeValid ? item.duration.seconds: 0)
        //
        let currentTimeText = textForPlaybackTime(time: item.currentTime().seconds)
        let remaningTimeText = "-\(textForPlaybackTime(time: item.duration.seconds - item.currentTime().seconds))"
        let durationText = textForPlaybackTime(time: item.duration.seconds)
        let sliderValue = Float(isTimeValid ? item.currentTime().seconds : 0)
        
        // update the external view if there is any
        externalControlsView?.updateSlider(maxValue: maxValue, availableValue: availableValue, currentValue: sliderValue)
        externalControlsView?.currentTime(text: currentTimeText)
        externalControlsView?.remainingTime(text: remaningTimeText)
        externalControlsView?.duration(text: durationText)
        
        if let playbackSlider = getViewForElementWithIdentifier("playback") as? Slider {
            playbackSlider.maximumValue = maxValue
            if !seeking {
                playbackSlider.setValue(value: sliderValue, animatedForDuration: MobilePlayerViewController.playbackInterfaceUpdateInterval)
            }
            
            playbackSlider.setAvailableValue(
                availableValue: availableValue,
                animatedForDuration: MobilePlayerViewController.playbackInterfaceUpdateInterval)
        }
        if let currentTimeLabel = getViewForElementWithIdentifier("currentTime") as? Label {
            currentTimeLabel.text = currentTimeText
            currentTimeLabel.superview?.setNeedsLayout()
        }
        if let remainingTimeLabel = getViewForElementWithIdentifier("remainingTime") as? Label {
            remainingTimeLabel.text = remaningTimeText
            remainingTimeLabel.superview?.setNeedsLayout()
        }
        if let durationLabel = getViewForElementWithIdentifier("duration") as? Label {
            durationLabel.text = durationText
            durationLabel.superview?.setNeedsLayout()
        }
        updateShownTimedOverlays()
    }
    
    private func textForPlaybackTime(time: TimeInterval) -> String {
        if !time.isNormal {
            return "00:00"
        }
        let hours = Int(floor(time / 3600))
        let minutes = Int(floor((time / 60).truncatingRemainder(dividingBy: 60)))
        let seconds = Int(floor(time.truncatingRemainder(dividingBy: 60)))
        let minutesAndSeconds = NSString(format: "%02d:%02d", minutes, seconds) as String
        if hours > 0 {
            return NSString(format: "%02d:%@", hours, minutesAndSeconds) as String
        } else {
            return minutesAndSeconds
        }
    }
    
    private func resetHideControlsTimer() {
        hideControlsTimer?.invalidate()
        hideControlsTimer = Timer.scheduledTimerWithTimeInterval(
            ti: 3,
            callback: {
                self.controlsView.controlsHidden = (self.state == .playing) || !self.didUserTap
                self.externalControlsView?.setControls(hidden:  (self.state == .playing) || !self.didUserTap, animated: true, nil)
        },
            repeats: false
        )
    }
    
    // TODO: Change accordingly later on
    private func handleMoviePlayerPlaybackStateDidChangeNotification() {
        state = StateHelper.calculateStateUsing(previousState: previousState, andPlaybackState: moviePlayer.timeControlStatus)
        playerStateChanged(from: previousState, to: state)
        externalControlsView?.playerStateDidChange(state)
        let playButton = getViewForElementWithIdentifier("play") as? ToggleButton
        if state == .playing {
            doFirstPlaySetupIfNeeded()
            playButton?.toggled = true
            if !controlsView.controlsHidden, let timer = hideControlsTimer, !timer.isValid {
                resetHideControlsTimer()
            }
            prerollViewController?.dismiss()
            pauseOverlayViewController?.dismiss()
            postrollViewController?.dismiss()
        } else {
            playButton?.toggled = false
            hideControlsTimer?.invalidate()
            if let pauseOverlayViewController = pauseOverlayViewController, (state == .paused && !seeking) {
                showOverlayViewController(pauseOverlayViewController)
            }
        }
    }
    
    private func updateShownTimedOverlays() {
        guard let item = moviePlayer?.currentItem else { return }
        
        if !(item.duration.isValid && item.duration.isNumeric) {
            return
        }
        
        let currentTime = item.currentTime().seconds
        
        DispatchQueue.global().async {
            for timedOverlayInfo in self.timedOverlays {
                if timedOverlayInfo.startTime <= currentTime && currentTime <= timedOverlayInfo.startTime + timedOverlayInfo.duration {
                    if timedOverlayInfo.overlay.parent == nil {
                        DispatchQueue.main.async {
                            self.showOverlayViewController(timedOverlayInfo.overlay)
                        }
                    }
                } else if timedOverlayInfo.overlay.parent != nil {
                    DispatchQueue.main.async {
                        timedOverlayInfo.overlay.dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - MobilePlayerOverlayViewControllerDelegate
extension MobilePlayerViewController: MobilePlayerOverlayViewControllerDelegate {
    
    func dismiss(mobilePlayerOverlayViewController overlayViewController: MobilePlayerOverlayViewController) {
        overlayViewController.willMove(toParent: nil)
        overlayViewController.view.removeFromSuperview()
        overlayViewController.removeFromParent()
        if overlayViewController == prerollViewController {
            play()
        }
    }
}

// MARK: - TimeSliderDelegate
extension MobilePlayerViewController: SliderDelegate {
    
    public func sliderThumbPanDidBegin(slider: Slider) {
        seeking = true
        wasPlayingBeforeSeek = (state == .playing)
        pause()
    }
    
    public func sliderThumbDidPan(slider: Slider) {}
    
    public func sliderThumbPanDidEnd(slider: Slider) {
        seeking = false
        guard let item = moviePlayer?.currentItem, item.duration.isValid, item.duration.isNumeric else { return }
        
        moviePlayer.seek(to: slider.value.cmTime)
        if wasPlayingBeforeSeek {
            play()
        }
    }
}


extension MobilePlayerViewController: PlayerItemStatusDelegate {
    
    public func cycleDidMove(_ player: AVPlayer, time: CMTime) {
        self.handleMoviePlayerPlaybackStateDidChangeNotification()
        
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: MobilePlayerStateDidChangeNotification), object: self)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.updatePlaybackInterface()
        }
    }
    
    public func playerDidFinish(_ player: AVPlayer) {
        if shouldAutoRepeat {
            player.seek(to: .zero)
        } else {
            if let postrollVC = postrollViewController {
                prerollViewController?.dismiss()
                pauseOverlayViewController?.dismiss()
                willShowPostrollViewController(postrollVC)
                showOverlayViewController(postrollVC)
            }
        }
    }
    
    public func statusDidChange(_ status: AVPlayerItem.Status, item: AVPlayerItem) {
        switch status {
        case .failed:
            NotificationCenter.default.post(name: NSNotification.Name(rawValue: MobilePlayerDidEncounterErrorNotification), object: self, userInfo: [MobilePlayerErrorUserInfoKey:
                moviePlayer.error as Any])
        case .readyToPlay:
            self.readyToPlay()
        default:
            print(status)
        }
    }
    
    
}


private extension Float {
    var cmTime: CMTime {
        CMTime(seconds: Double(self), preferredTimescale: CMTimeScale(NSEC_PER_SEC))
    }
}

