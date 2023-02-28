//
//  WelcomeScreen.m
//  GBA4iOS
//
//  Created by Clemens Schäfer on 28.02.23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

#import "WelcomeScreen.h"

@interface WelcomeScreen ()
@property (weak, nonatomic) IBOutlet UIImageView *appLogo;
@property (weak, nonatomic) IBOutlet UILabel *welcomeLabel;
@property (weak, nonatomic) IBOutlet UITextView *welcomeText;
@property (weak, nonatomic) IBOutlet UIButton *okButton;
@property (weak, nonatomic) IBOutlet UIButton *displayAgainButton;

@end

@implementation WelcomeScreen

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.modalInPresentation = true;
    
    self.welcomeLabel.text = NSLocalizedString(@"Welcome to GBA4iOS!", @"");
    self.welcomeText.text = NSLocalizedString(@"If at any time the app fails to open, please set the date back on your device at least 24 hours, then try opening the app again. Once the app is opened, you can set the date back to the correct time, and the app will continue to open normally. However, you'll need to repeat this process every time you restart your device.", @"");
    
    self.okButton.layer.cornerRadius = 10.0;
    self.okButton.layer.masksToBounds = true;
    
    [[self okButton] setTitle:NSLocalizedString(@"Continue", @"") forState:UIControlStateNormal];
    [[self displayAgainButton] setTitle:NSLocalizedString(@"Show again", @"") forState:UIControlStateNormal];
}

- (IBAction)okClicked:(id)sender {
    [self dismissViewControllerAnimated:true completion:^{
        [[NSUserDefaults standardUserDefaults] setObject:[NSDate date] forKey:@"showedWarningAlert"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }];
}
- (IBAction)displayAgainClicked:(id)sender {
    [self dismissViewControllerAnimated:true completion:nil];
}


@end
