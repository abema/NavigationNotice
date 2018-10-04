//
//  NavigationNotice.swift
//  NavigationNotice
//
//  Created by Kyohei Ito on 2015/02/06.
//  Copyright (c) 2015年 kyohei_ito. All rights reserved.
//

import UIKit

protocol SafeAreaInsetsEventCapture {
    var didChangeSafeAreaInsets: ((UIEdgeInsets) -> Void)? { get }
}

open class NavigationNotice {
    class ViewController: UIViewController, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        class HitView: UIView, SafeAreaInsetsEventCapture {
            var didChangeSafeAreaInsets: ((UIEdgeInsets) -> Void)?
            
            override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
                if let superView = super.hitTest(point, with: event) {
                    if superView != self {
                        return superView
                    }
                }
                return nil
            }
            
            @available(iOS 11, *)
            override func safeAreaInsetsDidChange() {
                super.safeAreaInsetsDidChange()
                didChangeSafeAreaInsets?(safeAreaInsets)
            }
        }
        
        class HitScrollView: UIScrollView {
            override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
                if let superView = super.hitTest(point, with: event) {
                    if superView != self {
                        return superView
                    }
                }
                return nil
            }
        }
        
        fileprivate var position: NoticePosition = .top
        fileprivate lazy var panGesture: UIPanGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(ViewController.panGestureAction(_:)))
        fileprivate var scrollPanGesture: UIPanGestureRecognizer? {
            return noticeView.gestureRecognizers?.filter({ $0 as? UIPanGestureRecognizer != nil }).first as? UIPanGestureRecognizer
        }
        fileprivate lazy var noticeView: HitScrollView = HitScrollView(frame: self.view.bounds)
        fileprivate weak var targetView: UIView? {
            didSet { targerWindow = targetView?.window }
        }
        fileprivate weak var targerWindow: UIWindow?
        fileprivate var targetController: UIViewController? {
            return targerWindow?.rootViewController
        }
        fileprivate var childController: UIViewController? {
            return targetController?.presentedViewController ?? targetController
        }
        fileprivate var contentView: UIView?
        fileprivate var autoHidden: Bool = false
        fileprivate var hiddenTimeInterval: TimeInterval = 0
        fileprivate var contentHeight: CGFloat {
            return noticeView.bounds.height
        }
        fileprivate var contentOffsetY: CGFloat {
            set { noticeView.contentOffset.y = newValue }
            get { return noticeView.contentOffset.y }
        }
        fileprivate var hiddenTimer: Timer? {
            didSet {
                oldValue?.invalidate()
            }
        }
        fileprivate var isShowSafeArea: Bool = true
        private var safeAreaInsets: UIEdgeInsets {
            if #available(iOS 11, *), isShowSafeArea {
                return view.safeAreaInsets
            } else {
                return .zero
            }
        }
        fileprivate var onStatusBar: Bool = true
        
        var showAnimations: ((@escaping () -> Void, @escaping (Bool) -> Void) -> Void)?
        var hideAnimations: ((@escaping () -> Void, @escaping (Bool) -> Void) -> Void)?
        var hideCompletionHandler: (() -> Void)?
        
        override var shouldAutorotate : Bool {
            return childController?.shouldAutorotate
                ?? super.shouldAutorotate
        }
        
        override var supportedInterfaceOrientations : UIInterfaceOrientationMask {
            return childController?.supportedInterfaceOrientations
                ?? super.supportedInterfaceOrientations
        }
        
        override var preferredInterfaceOrientationForPresentation : UIInterfaceOrientation {
            return childController?.preferredInterfaceOrientationForPresentation
                ?? super.preferredInterfaceOrientationForPresentation
        }
        
        override var childForStatusBarStyle : UIViewController? {
            return childController
        }
        
        override var childForStatusBarHidden : UIViewController? {
            return childController
        }
        
        override func loadView() {
            super.loadView()
            let hitView = HitView(frame: view.bounds)
            view = hitView
            hitView.didChangeSafeAreaInsets = { [weak self] safeAreaInsets in
                guard let me = self else { return }
                let insets: UIEdgeInsets = me.isShowSafeArea ? safeAreaInsets : .zero
                let needsUpdateOffset = me.isShowSafeArea ? me.contentView?.superview != nil : false
                me.layoutNoticeViewsIfNeeded(with: insets, needsUpdateOffset: needsUpdateOffset)
            }
        }
        
        override func viewDidLoad() {
            super.viewDidLoad()
            
            panGesture.delegate = self
            
            noticeView.clipsToBounds = false
            noticeView.showsVerticalScrollIndicator = false
            noticeView.isPagingEnabled = true
            noticeView.bounces = false
            noticeView.delegate = self
            switch position {
            case .top:
                noticeView.autoresizingMask = .flexibleWidth
            case .bottom:
                noticeView.autoresizingMask = [.flexibleWidth, .flexibleTopMargin, .flexibleBottomMargin]
            }
            view.addSubview(noticeView)
        }
        
        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            noticeView.contentSize.width = view.bounds.width
        }
        
        func setInterval(_ interval: TimeInterval) {
            hiddenTimeInterval = interval
            
            if interval >= 0 {
                autoHidden = true
                
                if panGesture.view != nil {
                    timer(interval)
                }
            } else {
                autoHidden = false
            }
        }
        
        func setContent(_ view: UIView) {
            contentView = view
        }
        
        func removeContent() {
            contentView?.removeFromSuperview()
            contentView = nil
        }
        
        func timer(_ interval: TimeInterval) {
            let handler: (CFRunLoopTimer?) -> Void = { [weak self] timer in
                self?.hiddenTimer = nil
                
                if self?.autoHidden == true {
                    if self?.panGesture.state != .changed && self?.scrollPanGesture?.state != .some(.changed) {
                        self?.hide(true)
                    }
                }
            }
            
            if interval > 0 {
                let fireDate = interval + CFAbsoluteTimeGetCurrent()
                let timer = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault, fireDate, 0, 0, 0, handler)
                CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, CFRunLoopMode.commonModes)
                hiddenTimer = timer
            } else {
                handler(nil)
            }
        }
        
        func showOn(_ view: UIView) {
            targetView = view
            
            if let contentView = contentView {
                contentView.autoresizingMask = .flexibleWidth
                noticeView.addSubview(contentView)
                contentView.setNeedsDisplay()
                layoutNoticeViewsIfNeeded(with: safeAreaInsets, needsUpdateOffset: false)
            }
            
            show() {
                self.targetView?.addGestureRecognizer(self.panGesture)
                
                if self.autoHidden == true {
                    self.timer(self.hiddenTimeInterval)
                }
            }
        }
        
        func show(_ completion: @escaping () -> Void) {
            showContent({
                switch self.position {
                case .top:
                    self.contentOffsetY = -self.contentHeight
                case .bottom:
                    self.contentOffsetY = self.contentHeight
                }
                self.setNeedsStatusBarAppearanceUpdateIfNeeded()
                }) { _ in
                    completion()
            }
        }
        
        func hide(_ animated: Bool) {
            targetView?.removeGestureRecognizer(panGesture)
            hiddenTimer = nil
            autoHidden = false
            
            if animated == true {
                hideContent({
                    self.contentOffsetY = 0
                    self.setNeedsStatusBarAppearanceUpdateIfNeeded()
                    }) { _ in
                        self.removeContent()
                        self.hideCompletionHandler?()
                }
            } else {
                self.setNeedsStatusBarAppearanceUpdateIfNeeded()
                removeContent()
                hideCompletionHandler?()
            }
        }
        
        func hideIfNeeded(_ animated: Bool) {
            if autoHidden == true && hiddenTimer == nil {
                hide(animated)
            }
        }
        
        @objc func panGestureAction(_ gesture: UIPanGestureRecognizer) {
            if (position == .top && contentOffsetY >= 0) || position == .bottom && contentOffsetY < 0 {
                hide(false)
                return
            }
            
            let locationOffsetY = gesture.location(in: view).y
            
            if gesture.state == .changed {
                switch position {
                case .top:
                    contentOffsetY = contentHeight > locationOffsetY ? -locationOffsetY : -contentHeight
                case .bottom:
                    contentOffsetY = view.bounds.height - contentHeight < locationOffsetY ? view.bounds.height - locationOffsetY : contentHeight
                }
            } else if gesture.state == .cancelled || gesture.state == .ended {
                let isHideIfNeeded, shouldShow: Bool
                switch position {
                case .top:
                    isHideIfNeeded = contentHeight < locationOffsetY
                    shouldShow = gesture.velocity(in: view).y > 0
                case .bottom:
                    isHideIfNeeded = view.bounds.height - contentHeight > locationOffsetY
                    shouldShow = gesture.velocity(in: view).y < 0
                }
                
                if isHideIfNeeded {
                    contentOffsetY = position == .top ? -contentHeight : contentHeight
                    hideIfNeeded(true)
                    return
                }
                
                if shouldShow {
                    show() {
                        self.hideIfNeeded(true)
                    }
                } else {
                    hide(true)
                }
            }
        }
        
        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            let needsHideAnimation = (position == .top && contentOffsetY < 0) || (position == .bottom && contentOffsetY >= contentHeight)
            if needsHideAnimation {
                resetTimerIfNeeded()
            } else {
                hide(false)
            }
        }
        
        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if autoHidden == true && decelerate == false && hiddenTimer == nil {
                timer(hiddenTimeInterval)
            }
        }
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return gestureRecognizer == panGesture || otherGestureRecognizer == panGesture
        }
        
        func showContent(_ animations: @escaping () -> Void, completion: @escaping (Bool) -> Void) {
            if let show = showAnimations {
                show(animations, completion)
            } else {
                UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0, options: .beginFromCurrentState, animations: animations, completion: completion)
            }
        }
        
        func hideContent(_ animations: @escaping () -> Void, completion: @escaping (Bool) -> Void) {
            if let hide = hideAnimations {
                hide(animations, completion)
            } else {
                UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 1, options: .beginFromCurrentState, animations: animations, completion: completion)
            }
        }
        
        fileprivate func setNeedsStatusBarAppearanceUpdateIfNeeded() {
            if onStatusBar == true {
                setNeedsStatusBarAppearanceUpdate()
            }
        }
        
        private func resetTimerIfNeeded() {
            if autoHidden == true {
                timer(hiddenTimeInterval)
            }
        }
        
        private func layoutNoticeViewsIfNeeded(with safeAreaInsets: UIEdgeInsets, needsUpdateOffset: Bool) {
            if let contentView = contentView {
                noticeView.frame.size.height = contentView.bounds.height
                contentView.frame.size.width = noticeView.bounds.width - safeAreaInsets.right - safeAreaInsets.left
                
                noticeView.contentSize = noticeView.bounds.size
                switch position {
                case .top:
                    noticeView.frame.size.height += safeAreaInsets.top
                    noticeView.contentInset.top = contentHeight
                    noticeView.contentInset.bottom = safeAreaInsets.top
                    noticeView.frame.origin = .zero
                    contentView.frame.origin = CGPoint(x: (safeAreaInsets.right + safeAreaInsets.left) / 2,
                                                       y: -contentHeight + safeAreaInsets.top)
                case .bottom:
                    noticeView.frame.size.height += safeAreaInsets.bottom
                    noticeView.contentInset.bottom = contentHeight + safeAreaInsets.bottom
                    noticeView.frame.origin = CGPoint(x: 0, y: self.view.bounds.height - contentHeight)
                    contentView.frame.origin = CGPoint(x: (safeAreaInsets.right + safeAreaInsets.left) / 2,
                                                       y: contentHeight)
                }
                
                if needsUpdateOffset {
                    contentOffsetY = position == .top ? -contentHeight : contentHeight
                }
            }
        }
    }

    fileprivate class NoticeManager {
        class HitWindow: UIWindow {
            override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
                if let superWindow = super.hitTest(point, with: event) {
                    if superWindow != self {
                        return superWindow
                    }
                }
                return nil
            }
        }
        
        fileprivate weak var mainWindow: UIWindow?
        fileprivate var noticeWindow: HitWindow?
        fileprivate var contents: [NavigationNotice] = []
        fileprivate var showingNotice: NavigationNotice?
        fileprivate var onStatusBar: Bool = true
        fileprivate var showAnimations: ((@escaping () -> Void, @escaping (Bool) -> Void) -> Void)?
        fileprivate var hideAnimations: ((@escaping () -> Void, @escaping (Bool) -> Void) -> Void)?
        
        fileprivate func startNotice(_ notice: NavigationNotice) {
            showingNotice = notice
            
            noticeWindow?.rootViewController = notice.noticeViewController
            noticeWindow?.windowLevel = UIWindow.Level.statusBar + (notice.onStatusBar ? 1 : -1)
            
            if let view = notice.noticeViewController.targetView {
                mainWindow = view.window
                
                notice.noticeViewController.showOn(view)
            }
        }
        
        fileprivate func endNotice() {
            showingNotice?.noticeViewController.setNeedsStatusBarAppearanceUpdateIfNeeded()
            showingNotice = nil
            
            mainWindow?.makeKeyAndVisible()
            noticeWindow = nil
        }
        
        func next() {
            if let notice = pop() {
                startNotice(notice)
            } else {
                endNotice()
            }
        }
        
        func add(_ notice: NavigationNotice) {
            contents.append(notice)
            
            DispatchQueue.main.async {
                if self.showingNotice == nil {
                    self.noticeWindow = HitWindow(frame: UIScreen.main.bounds)
                    self.noticeWindow?.makeKeyAndVisible()
                    
                    self.next()
                }
            }
        }
        
        func pop() -> NavigationNotice? {
            if contents.count >= 1 {
                return contents.remove(at: 0)
            }
            return nil
        }
        
        func removeAll() {
            contents.removeAll()
        }
    }
    
    public enum NoticePosition {
        case top
        case bottom
    }
    
    fileprivate var noticeViewController = ViewController()
    fileprivate var onStatusBar: Bool = NavigationNotice.defaultOnStatusBar {
        didSet { noticeViewController.onStatusBar = onStatusBar }
    }
    fileprivate var completionHandler: (() -> Void)?
    open var existCompletionHandler: Bool {
        return completionHandler != nil
    }
    /// Common navigation bar on the status bar. Default is `true`.
    open class var defaultOnStatusBar: Bool {
        set { sharedManager.onStatusBar = newValue }
        get { return sharedManager.onStatusBar }
    }
    fileprivate var showAnimations: ((@escaping () -> Void, @escaping (Bool) -> Void) -> Void)? = NavigationNotice.defaultShowAnimations
    /// Common animated block of show. Default is `nil`.
    open class var defaultShowAnimations: ((@escaping () -> Void, @escaping (Bool) -> Void) -> Void)? {
        set { sharedManager.showAnimations = newValue }
        get { return sharedManager.showAnimations }
    }
    fileprivate var hideAnimations: ((@escaping () -> Void, @escaping (Bool) -> Void) -> Void)? = NavigationNotice.defaultHideAnimations
    /// Common animated block of hide. Default is `nil`.
    open class var defaultHideAnimations: ((@escaping () -> Void, @escaping (Bool) -> Void) -> Void)? {
        set { sharedManager.hideAnimations = newValue }
        get { return sharedManager.hideAnimations }
    }
    fileprivate static let sharedManager = NoticeManager()
    
    /// Notification currently displayed.
    open class func currentNotice() -> NavigationNotice? {
        return sharedManager.showingNotice
    }
    
    /// Add content to display.
    @discardableResult
    open class func addContent(_ view: UIView) -> NavigationNotice {
        let notice = NavigationNotice()
        notice.noticeViewController.setContent(view)
        
        return notice
    }
    
    /// Set on the status bar of notification.
    @discardableResult
    open class func onStatusBar(_ on: Bool) -> NavigationNotice {
        let notice = NavigationNotice()
        notice.onStatusBar = on
        
        return notice
    }
    
    @discardableResult
    open class func position(_ position: NoticePosition) -> NavigationNotice {
        let notice = NavigationNotice()
        notice.noticeViewController.position = position
        return notice
    }
    
    @discardableResult
    open class func isShowSafeArea(_ isShow: Bool) -> NavigationNotice {
        let notice = NavigationNotice()
        notice.noticeViewController.isShowSafeArea = isShow
        return notice
    }
    
    fileprivate init() {}
    
    /// Add content to display.
    @discardableResult
    open func addContent(_ view: UIView) -> Self {
        noticeViewController.setContent(view)
        
        if noticeViewController.targetView != nil {
            NavigationNotice.sharedManager.add(self)
        }
        
        return self
    }
    
    /// Show notification on view.
    @discardableResult
    open func showOn(_ view: UIView) -> Self {
        noticeViewController.showAnimations = showAnimations
        noticeViewController.hideAnimations = hideAnimations
        noticeViewController.targetView = view
        noticeViewController.hideCompletionHandler = { [weak self] in
            self?.completionHandler?()
            self?.completionHandler = nil
            NavigationNotice.sharedManager.next()
        }
        
        if noticeViewController.contentView != nil {
            NavigationNotice.sharedManager.add(self)
        }
        
        return self
    }
    
    /// Animated block of show.
    @discardableResult
    open func showAnimations(_ animations: @escaping (@escaping () -> Void, @escaping (Bool) -> Void) -> Void) -> Self {
        noticeViewController.showAnimations = animations
        
        return self
    }
    
    /// Hide notification.
    @discardableResult
    open func hide(_ interval: TimeInterval) -> Self {
        noticeViewController.setInterval(interval)
        return self
    }
    
    /// Animated block of hide.
    @discardableResult
    open func hideAnimations(_ animations: @escaping (@escaping () -> Void, @escaping (Bool) -> Void) -> Void) -> Self {
        noticeViewController.hideAnimations = animations
        
        return self
    }
    
    open func completion(_ completion: (() -> Void)?) {
        completionHandler = completion
    }
    
    /// Remove all notification.
    @discardableResult
    open func removeAll(_ hidden: Bool) -> Self {
        let notice = NavigationNotice.sharedManager
        notice.removeAll()
        
        if hidden {
            _ = notice.showingNotice?.hide(0)
        }
        
        return self
    }
    
    @discardableResult
    open func position(_ position: NoticePosition) -> Self {
        noticeViewController.position = position
        return self
    }
    
    @discardableResult
    open func isShowSafeArea(_ isShow: Bool) -> Self {
        noticeViewController.isShowSafeArea = isShow
        return self
    }
}
