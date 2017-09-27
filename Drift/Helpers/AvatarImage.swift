//
//  AvatarImage.swift
//  Drift
//
//  Created by Brian McDonald on 19/06/2017.
//  Copyright © 2017 Drift. All rights reserved.
//

import UIKit
import AlamofireImage

protocol AvatarDelegate {
    func avatarPressed()
}

@IBDesignable class AvatarView: UIView {
    
    @IBInspectable var cornerRadius: CGFloat = 3{
        didSet{
            setUpCorners()
        }
    }
    
    var button = UIButton()
    var imageView = UIImageView()
    var initialsLabel = UILabel()
    var delegate: AvatarDelegate?
    
    var wiggleAnimation: CAKeyframeAnimation{
        let wiggleAnimation = CAKeyframeAnimation(keyPath: "transform")
        let wobbleAngle: CGFloat = 0.06
        
        let valLeft = NSValue(caTransform3D: CATransform3DMakeRotation(wobbleAngle, 0, 0, 1))
        let valRight = NSValue(caTransform3D: CATransform3DMakeRotation(-wobbleAngle, 0, 0, 1))
        
        wiggleAnimation.values = [valLeft, valRight]
        wiggleAnimation.autoreverses = true
        wiggleAnimation.duration = 0.125
        wiggleAnimation.repeatCount = Float.infinity
        
        return wiggleAnimation
    }
    
    @objc func buttonPressed() {
        delegate?.avatarPressed()
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        self.addSubview(imageView)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        let imageViewleadingConstraint = NSLayoutConstraint(item: imageView, attribute: NSLayoutAttribute.leading, relatedBy: NSLayoutRelation.equal, toItem: self, attribute: NSLayoutAttribute.leading, multiplier: 1, constant: 0)
        let imageViewtrailingConstraint = NSLayoutConstraint(item: imageView, attribute: NSLayoutAttribute.trailing, relatedBy: NSLayoutRelation.equal, toItem: self, attribute: NSLayoutAttribute.trailing, multiplier: 1, constant: 0)
        let imageViewtopConstraint = NSLayoutConstraint(item: imageView, attribute: NSLayoutAttribute.bottom, relatedBy: NSLayoutRelation.equal, toItem: self, attribute: NSLayoutAttribute.bottom, multiplier: 1, constant: 0)
        let imageViewbottomConstraint = NSLayoutConstraint(item: imageView, attribute: NSLayoutAttribute.top, relatedBy: NSLayoutRelation.equal, toItem: self, attribute: NSLayoutAttribute.top, multiplier: 1, constant: 0)
        self.addConstraints([imageViewleadingConstraint, imageViewtrailingConstraint, imageViewtopConstraint, imageViewbottomConstraint])
        
        self.addSubview(button)
        button.translatesAutoresizingMaskIntoConstraints = false
        let buttonLeadingConstraint = NSLayoutConstraint(item: button, attribute: NSLayoutAttribute.leading, relatedBy: NSLayoutRelation.equal, toItem: self, attribute: NSLayoutAttribute.leading, multiplier: 1, constant: 0)
        let buttonTrailingConstraint = NSLayoutConstraint(item: button, attribute: NSLayoutAttribute.trailing, relatedBy: NSLayoutRelation.equal, toItem: self, attribute: NSLayoutAttribute.trailing, multiplier: 1, constant: 0)
        let buttonTopConstraint = NSLayoutConstraint(item: button, attribute: NSLayoutAttribute.bottom, relatedBy: NSLayoutRelation.equal, toItem: self, attribute: NSLayoutAttribute.bottom, multiplier: 1, constant: 0)
        let buttonBottomConstraint = NSLayoutConstraint(item: button, attribute: NSLayoutAttribute.top, relatedBy: NSLayoutRelation.equal, toItem: self, attribute: NSLayoutAttribute.top, multiplier: 1, constant: 0)
        self.addConstraints([buttonLeadingConstraint, buttonTrailingConstraint, buttonTopConstraint, buttonBottomConstraint])
        
        button.addTarget(self, action: #selector(AvatarView.buttonPressed), for: UIControlEvents.touchUpInside)
        
        self.addSubview(initialsLabel)
        imageView.contentMode = .scaleAspectFill
        imageView.backgroundColor = UIColor.red
        layer.masksToBounds = true
        layer.borderWidth = 0
        layer.borderColor = UIColor(white: 0, alpha: 0.1).cgColor
        backgroundColor = ColorPalette.grayColor
        initialsLabel.isHidden = true
        
        setUpCorners()
    }
    
    func setUpCorners(){
        layer.cornerRadius = cornerRadius
    }
    
    func setUpForAvatarURL(avatarUrl: String?){
        if let avatarUrl = avatarUrl{
            if let url = URL(string: avatarUrl){
                
                initialsLabel.isHidden = true
                let filter = AspectScaledToFillSizeFilter(
                    size: self.frame.size
                )
                
                imageView.backgroundColor = UIColor.clear
                imageView.isHidden = false
                imageView.layer.add(wiggleAnimation, forKey: "wiggle")
                
                let placeholder = UIImage(named: "placeholderAvatar", in: Bundle(for: Drift.self), compatibleWith: nil)
                let placeholderScaled = placeholder?.af_imageAspectScaled(toFill: self.frame.size)
                
                imageView.af_setImage(withURL: url, placeholderImage: nil, filter: filter, imageTransition: .crossDissolve(0.1), runImageTransitionIfCached: false, completion: { result in
                    
                    self.initialsLabel.text = ""
                    switch result.result {
                    case .success(let image):
                        self.imageView.image = image.af_imageAspectScaled(toFill: self.frame.size)
                        self.initialsLabel.isHidden = true
                    case .failure(_):
                        self.imageView.image = placeholderScaled
                        
                    }
                    self.imageView.layer.removeAllAnimations()
                    
                })
            }
        }else{
            let placeholder = UIImage(named: "placeholderAvatar", in: Bundle(for: Drift.self), compatibleWith: nil)
            let placeholderScaled = placeholder?.af_imageAspectScaled(toFill: self.frame.size)
            self.imageView.image = placeholderScaled
        }
    }
    
    func setupForBot(embed: Embed?){
        imageView.image = #imageLiteral(resourceName: "robot")
        if let backgroundColorString = embed?.backgroundColorString {
            let color = UIColor(hexString: "#\(backgroundColorString)")
            imageView.backgroundColor = color
        }else{
            imageView.backgroundColor = ColorPalette.driftBlue
        }
    }
    
}
