//
//  GBAROMTableViewController.m
//  GBA4iOS
//
//  Created by Riley Testut on 7/18/13.
//  Copyright (c) 2013 Riley Testut. All rights reserved.
//

#import "GBAROMTableViewController.h"
#import "GBAEmulationViewController.h"
#import "GBASettingsViewController.h"
#import "GBAROM_Private.h"
#import "RSTFileBrowserTableViewCell+LongPressGestureRecognizer.h"
#import "GBAMailActivity.h"
#import "GBASplitViewController.h"
#import "UITableViewController+Theming.h"
#import "GBAControllerSkin.h"
#import "GBASyncManager.h"
#import "GBASyncingDetailViewController.h"
#import "GBAAppDelegate.h"
#import "NSFileManager+ForcefulMove.h"
#import "WelcomeScreen.h"
#import "GBACheatManagerViewController.h"

#import <Crashlytics/Crashlytics.h>

#import "UIAlertView+RSTAdditions.h"
#import "UIActionSheet+RSTAdditions.h"

#import "SSZipArchive.h"
#import <ObjectiveDropboxOfficial/ObjectiveDropboxOfficial.h>

#define LEGAL_NOTICE_ALERT_TAG 15
#define NAME_ROM_ALERT_TAG 17
#define DELETE_ROM_ALERT_TAG 2
#define RENAME_GESTURE_RECOGNIZER_TAG 22

#define OVERWRITE_DEFAULT_SKIN 0

static void * GBADownloadROMProgressContext = &GBADownloadROMProgressContext;

typedef NS_ENUM(NSInteger, GBAVisibleROMType) {
    GBAVisibleROMTypeAll,
    GBAVisibleROMTypeGBA,
    GBAVisibleROMTypeGBC,
};

// PEEK POP
// UIViewControllerPreviewingDelegate, UIViewControllerPreviewing
@interface GBAROMTableViewController () <UIAlertViewDelegate, UIViewControllerTransitioningDelegate, UIPopoverControllerDelegate, GBASettingsViewControllerDelegate, GBASyncingDetailViewControllerDelegate, GBASplitViewControllerEmulationDelegate, UITextFieldDelegate>
{
    BOOL _performedInitialRefreshDirectory;
}

@property (assign, nonatomic) GBAVisibleROMType visibleRomType;
@property (strong, nonatomic) NSMutableSet *currentUnzippingOperations;

@property (weak, nonatomic) IBOutlet UIBarButtonItem *filterButton;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *settingsButton;
@property (strong, nonatomic) UIPopoverController *activityPopoverController;
@property (strong, nonatomic) NSIndexPath *selectedROMIndexPath;

@property (strong, nonatomic) IBOutlet UILabel *noGamesLabel;
@property (strong, nonatomic) IBOutlet UILabel *noGamesDescriptionLabel;

@property (assign, nonatomic) BOOL dismissModalViewControllerUponKeyboardHide;

@property (assign, nonatomic, getter = isAwaitingDownloadHTTPResponse) BOOL awaitingDownloadHTTPResponse;
@property (strong, nonatomic) NSProgress *downloadProgress;
@property (strong, nonatomic) UIProgressView *downloadProgressView;
@property (strong, nonatomic) NSMutableDictionary *currentDownloadsDictionary;

- (IBAction)presentSettings:(UIBarButtonItem *)barButtonItem;


@end

@implementation GBAROMTableViewController
@synthesize theme = _theme;




dispatch_queue_t directoryContentsChangedQueue() {
    static dispatch_once_t queueCreationGuard;
    static dispatch_queue_t queue;
    dispatch_once(&queueCreationGuard, ^{
        queue = dispatch_queue_create("de.ceviixx.GBA4iOS.directory_contents_changed_queue", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Emulation" bundle:nil];
    self = [storyboard instantiateViewControllerWithIdentifier:@"romTableViewController"];
    if (self)
    {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *documentsDirectory = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
        
        self.currentDirectory = documentsDirectory; 
        self.showFileExtensions = YES;
        self.showFolders = NO;
        self.showSectionTitles = YES;
        self.showUnavailableFiles = YES;
        
        _downloadProgress = [[NSProgress alloc] initWithParent:nil userInfo:nil];
        [_downloadProgress addObserver:self
                    forKeyPath:@"fractionCompleted"
                       options:NSKeyValueObservingOptionNew
                       context:GBADownloadROMProgressContext];
        
        _currentDownloadsDictionary = [NSMutableDictionary dictionary];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(userRequestedToPlayROM:) name:GBAUserRequestedToPlayROMNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardDidHide:) name:UIKeyboardDidHideNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(settingsDidChange:) name:GBASettingsDidChangeNotification object:nil];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}


- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.
    
    self.clearsSelectionOnViewWillAppear = YES;
    
    GBAVisibleROMType romType = (GBAVisibleROMType)[[NSUserDefaults standardUserDefaults] integerForKey:@"visibleROMType"];
    self.romType = romType;
    
    [self.tableView registerClass:[UITableViewHeaderFooterView class] forHeaderFooterViewReuseIdentifier:@"Header"];
    
    [self importDefaultSkins];
    
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
    {
        [(GBASplitViewController *)self.splitViewController setEmulationDelegate:self];
    }
    
    [self setupFilterMenu:@"all"];
}

-(void) setupFilterMenu:(NSString *) activeRomType
{
    
    NSMutableArray* filterActions = [[NSMutableArray alloc] init];
    [filterActions addObject:[
        UIAction actionWithTitle:NSLocalizedString(@"ALL", @"") image:nil identifier:@"all" handler:^(__kindof UIAction* _Nonnull action) {
        [self setRomType: GBAVisibleROMTypeAll];
    }]];
    [filterActions addObject:[UIAction actionWithTitle:NSLocalizedString(@"Gameboy Advance", @"") image:nil identifier:@"gba" handler:^(__kindof UIAction* _Nonnull action) {
        [self setRomType: GBAVisibleROMTypeGBA];
    }]];
    [filterActions addObject:[UIAction actionWithTitle:NSLocalizedString(@"Gameboy Color", @"") image:nil identifier:@"gbc" handler:^(__kindof UIAction* _Nonnull action) {
        [self setRomType: GBAVisibleROMTypeGBC];
    }]];
    
    for (UIAction *action in filterActions)
    {
        if (action.identifier == activeRomType)
        {
            action.state = UIMenuElementStateOn;
        }
    }
    
    UIMenu *filterMenu = [UIMenu menuWithTitle:NSLocalizedString(@"Filter games", @"") children:filterActions];
    self.filterButton.menu = filterMenu;
}

UITapGestureRecognizer *cancelRenamingGesture;

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point {
    NSString *filepath = [self filepathForIndexPath:indexPath];
    NSString *romName = [[filepath lastPathComponent] stringByDeletingPathExtension];
    
    GBAROM *rom = [GBAROM romWithContentsOfFile:filepath];
    
    UIContextMenuConfiguration* config = [UIContextMenuConfiguration configurationWithIdentifier:nil
                                                                                 previewProvider:nil
                                                                                  actionProvider:^UIMenu* _Nullable(NSArray<UIMenuElement*>* _Nonnull suggestedActions) {
        
        UIAction *deleteAction = [UIAction actionWithTitle:NSLocalizedString(@"Delete", @"") image:[UIImage systemImageNamed:@"trash"] identifier:nil handler:^(__kindof UIAction* _Nonnull action) {
            [self deleteForAtIndexPath:indexPath];
        }];
        
        UIAction *renameAction = [UIAction actionWithTitle:NSLocalizedString(@"Rename", @"") image:[UIImage systemImageNamed:@"pencil"] identifier:nil handler:^(__kindof UIAction* _Nonnull action) {
            
            [tableView scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionMiddle animated:true];
            RSTFileBrowserTableViewCell *renamingCell = [tableView cellForRowAtIndexPath:indexPath];
            [[renamingCell textLabel] setHidden:true];
            [[renamingCell detailTextLabel] setHidden:true];
            
            UITextField *renameText = [[UITextField alloc] initWithFrame:CGRectMake(16, 0, renamingCell.frame.size.width - 25, renamingCell.frame.size.height)];
            [renameText setTag:99];
            [renameText setAutocorrectionType:UITextAutocorrectionTypeYes];
            [renameText setReturnKeyType:UIReturnKeyDone];
            [renameText setText:romName];
            [renameText setPlaceholder:romName];
            [renameText setClearButtonMode:UITextFieldViewModeAlways];
            [renameText setDelegate:self];
            [renameText addTarget:self action:@selector(updateRomName:) forControlEvents:UIControlEventEditingDidEndOnExit];
            
            [renamingCell addSubview:renameText];
            [renameText becomeFirstResponder];
            
            [renamingCell setTag:indexPath.section];
            [renamingCell.textLabel setTag:indexPath.row];
        }];
        
        UIMenu* editMenu = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[renameAction, deleteAction]];
        
        
        
        
        UIAction *closeGameAction = [UIAction actionWithTitle:NSLocalizedString(@"Quit", @"") image:nil identifier:nil handler:^(__kindof UIAction * _Nonnull action) {
            
            
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Quit game?", @"")
                                                            message:NSLocalizedString(@"If you quit this game all unsaved data will be lost.", @"")
                                                           delegate:nil
                                                  cancelButtonTitle:NSLocalizedString(@"Cancel", @"")
                                                  otherButtonTitles:NSLocalizedString(@"Quit", @""), nil];
            [alert showWithSelectionHandler:^(UIAlertView *alertView, NSInteger buttonIndex) {
                if (buttonIndex == 1)
                {
                    self.emulationViewController.rom = nil;
                    [self.tableView reloadData];
                }
                if (buttonIndex == 0)
                {
                    [self.tableView reloadData];
                }
            }];
            
            
        }];
        
        UIMenu *closeGameMenu = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[closeGameAction]];
        
        UIAction *shareAction = [UIAction actionWithTitle:NSLocalizedString(@"Share", @"") image:[UIImage systemImageNamed:@"square.and.arrow.up"] identifier:nil handler:^(__kindof UIAction* _Nonnull action) {
            [self shareROMAtIndexPath:indexPath];
        }];
        
        UIAction *showCheatsAction = [UIAction actionWithTitle:NSLocalizedString(@"Cheats", @"") image:[UIImage systemImageNamed:@"ellipsis.curlybraces"] identifier:nil handler:^(__kindof UIAction* _Nonnull action) {
            GBACheatManagerViewController *cheatManagerViewController = [[GBACheatManagerViewController alloc] initWithROM:rom];
            
            UINavigationController *navigationController = RST_CONTAIN_IN_NAVIGATION_CONTROLLER(cheatManagerViewController);
            [self presentViewController:navigationController animated:true completion:nil];
            
            cheatManagerViewController.navigationItem.prompt = romName;
            navigationController.navigationBar.tintColor = UIColor.secondaryLabelColor;
        }];
        
        
        UIMenu* menu = [UIMenu menuWithTitle:@"" children:@[shareAction, showCheatsAction, editMenu]];
        if ([self.emulationViewController.rom isEqual:rom]) {
            menu = [UIMenu menuWithTitle:@"" children:@[shareAction, showCheatsAction, closeGameMenu]];
        }
        return menu;
    }];
    return config;
    
}

UITapGestureRecognizer *endEditingTapRecognizer;

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    NSLog(@"Did begin editing");
    
    endEditingTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(cancelRenameRomName:)];
    [endEditingTapRecognizer setNumberOfTapsRequired:1];
    [self.view addGestureRecognizer:endEditingTapRecognizer];
    
    [[self tableView] setScrollEnabled:false];
    [[self tableView] setAllowsSelection:false];
}


- (void)textFieldDidEndEditing:(UITextField *)textField {
    NSLog(@"Did end editing");
    RSTFileBrowserTableViewCell *cell = [textField superview];
    
    [[cell textLabel] setHidden:false];
    [[cell detailTextLabel] setHidden:false];
    [textField removeFromSuperview];
    
    [[self tableView] setScrollEnabled:true];
    [[self tableView] setAllowsSelection:true];
    
    [[self view] removeGestureRecognizer:endEditingTapRecognizer];
}


- (void) updateRomName:(UITextField*) textField {
    
    RSTFileBrowserTableViewCell *cell = [textField superview];
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:cell.textLabel.tag inSection:cell.tag];
    
    NSLog(@"Edit for %@ - %@", indexPath);
    
    NSLog(@"Indexpaht for editing: %@", indexPath);
    NSString *newName = [textField text];
    
    if ([[textField text] length] == 0) {
        newName = [textField placeholder];
    }
    
    [self renameROMAtIndexPath:indexPath toName:newName];
    
    [self.view endEditing:true];
    [self.tableView reloadData];
}


- (void) cancelRenameRomName:(UITapGestureRecognizer *)recognizer {
    NSLog(@"Cancel renaming tap");
    CGPoint location = [recognizer locationInView:[recognizer.view superview]];
    
    [self.view endEditing:true];
    [self.view removeGestureRecognizer:recognizer];
    
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    [[UIApplication sharedApplication] setStatusBarStyle:[self preferredStatusBarStyle] animated:YES];
        
    // Sometimes it loses its color when the view appears
//    self.downloadProgressView.progressTintColor = GBA4iOS_PURPLE_COLOR;
    self.downloadProgressView.progressTintColor = UIColor.systemBlueColor;
    
    if ([self.appearanceDelegate respondsToSelector:@selector(romTableViewControllerWillAppear:)])
    {
        [self.appearanceDelegate romTableViewControllerWillAppear:self];
    }
    
    if (self.emulationViewController.rom && [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) // Show selected ROM
    {
        [self.tableView reloadData];
    }
    
    if (self.selectedROMIndexPath &&
        self.selectedROMIndexPath.section < [self.tableView numberOfSections] &&
        self.selectedROMIndexPath.row < [self.tableView numberOfRowsInSection:self.selectedROMIndexPath.section] &&
        [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone)
    {
        [self.tableView scrollToRowAtIndexPath:self.selectedROMIndexPath atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
    }
    
    self.navigationController.navigationBar.prefersLargeTitles = true;
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    if ([self.appearanceDelegate respondsToSelector:@selector(romTableViewControllerWillDisappear:)])
    {
        [self.appearanceDelegate romTableViewControllerWillDisappear:self];
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        DLog(@"ROM list appeared");
        
        self.downloadProgressView = ({
            UIProgressView *progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleBar];
            progressView.frame = CGRectMake(0,
                                            CGRectGetHeight(self.navigationController.navigationBar.bounds) - CGRectGetHeight(progressView.bounds),
                                            CGRectGetWidth(self.navigationController.navigationBar.bounds),
                                            CGRectGetHeight(progressView.bounds));
            progressView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
            progressView.trackTintColor = [UIColor clearColor];
            progressView.progress = 0.0;
            progressView.alpha = 0.0;
            [self.navigationController.navigationBar addSubview:progressView];
            progressView;
        });
    });
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
    // Don't scroll when rotating, we can't guarantee the user wants to stay on this index path
    // [self.tableView scrollToRowAtIndexPath:self.selectedROMIndexPath atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
}

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    
//    [[UIApplication sharedApplication] setStatusBarHidden:[self prefersStatusBarHidden]];
}

- (BOOL)prefersStatusBarHidden
{
    return NO;
}

//- (UIStatusBarStyle)preferredStatusBarStyle
//{
//    if (self.theme == GBAThemedTableViewControllerThemeOpaque)
//    {
//        return UIStatusBarStyleDefault;
//    }
//
//    return UIStatusBarStyleLightContent;
//}

#pragma mark - Downloading Games


- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context == GBADownloadROMProgressContext)
    {
        NSProgress *progress = object;
        
        if (progress.fractionCompleted > 0)
        {
            dispatch_async(dispatch_get_main_queue(), ^{                
                [self.downloadProgressView setProgress:progress.fractionCompleted animated:YES];
            });
        }
        
        return;
    }
    
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}


- (void)keyboardDidHide:(NSNotification *)notification
{
    if (self.dismissModalViewControllerUponKeyboardHide)
    {
        self.dismissModalViewControllerUponKeyboardHide = NO;
        
        // Needs just a tiny delay to ensure that the romTableViewController resizes correctly after dismissal of the keyboard
        double delayInSeconds = 0.2;
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
            [self dismissViewControllerAnimated:YES completion:nil];
        });
        
    }
}

#pragma mark - UITableViewController data source

- (NSArray<NSString *> *)sectionIndexTitlesForTableView:(UITableView *)tableView {
    return nil;
}

- (NSInteger)tableView:(UITableView *)tableView sectionForSectionIndexTitle:(NSString *)title atIndex:(NSInteger)index {
    return 1;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    
    UIContextualAction *deleteRowAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:NSLocalizedString(@"Delete", @"") handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL))
        {
        [self deleteForAtIndexPath:indexPath];
        }];
    
    UIContextualAction *quitGameRowAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title: NSLocalizedString(@"Quit", @"") handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL))
        {
        
        
        
        
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Quit game?", @"")
                                                        message:NSLocalizedString(@"If you quit this game all unsaved data will be lost.", @"")
                                                       delegate:nil
                                              cancelButtonTitle:NSLocalizedString(@"Cancel", @"")
                                              otherButtonTitles:NSLocalizedString(@"Quit", @""), nil];
        [alert showWithSelectionHandler:^(UIAlertView *alertView, NSInteger buttonIndex) {
            if (buttonIndex == 1)
            {
                self.emulationViewController.rom = nil;
                [self.tableView reloadData];
            }
            if (buttonIndex == 0)
            {
                [self.tableView reloadData];
            }
        }];
        

        
        }];
    quitGameRowAction.backgroundColor = UIColor.systemOrangeColor;
    
    
    
    
    NSString *filepath = [self filepathForIndexPath:indexPath];
    GBAROM *rom = [GBAROM romWithContentsOfFile:filepath];
    
    if ([self.emulationViewController.rom isEqual:rom]) {
        UISwipeActionsConfiguration *config = [UISwipeActionsConfiguration configurationWithActions:@[quitGameRowAction]];
            return config;
    } else if (![self.emulationViewController.rom isEqual:rom]) {
        UISwipeActionsConfiguration *config = [UISwipeActionsConfiguration configurationWithActions:@[deleteRowAction]];
            return config;
    }
    
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    RSTFileBrowserTableViewCell *cell = (RSTFileBrowserTableViewCell *)[super tableView:tableView cellForRowAtIndexPath:indexPath];
    
    NSString *filename = [self filenameForIndexPath:indexPath];
    
    [self themeTableViewCell:cell];
    
    cell.textLabel.tag = indexPath.section;
    cell.detailTextLabel.tag = indexPath.row;
    [cell setTag:indexPath.section];
    
    NSString *lowercaseFileExtension = [filename.pathExtension lowercaseString];
    
    if ([self isDownloadingFile:filename] || [self.unavailableFiles containsObject:filename])
    {
        cell.userInteractionEnabled = NO;
        cell.textLabel.textColor = [UIColor grayColor];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        
        cell.textLabel.textColor = UIColor.systemRedColor;
        cell.detailTextLabel.textColor = UIColor.systemRedColor;
    }
    else if ([lowercaseFileExtension isEqualToString:@"zip"])
    {
        // Allows user to delete zip files if they're not being downloaded, but we'll still prevent them from opening them
        cell.userInteractionEnabled = YES;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.textColor = [UIColor grayColor];
        
        cell.textLabel.textColor = UIColor.secondaryLabelColor;
        cell.detailTextLabel.textColor = UIColor.tertiaryLabelColor;
    }
    else
    {
        GBAROMType romType = GBAROMTypeGBA;
        
        if ([lowercaseFileExtension isEqualToString:@"gbc"] || [lowercaseFileExtension isEqualToString:@"gb"])
        {
            romType = GBAROMTypeGBC;
        }
        
        // Use name so we don't have to load a uniqueName from disk for every cell
        if ([self.emulationViewController.rom.name isEqualToString:[filename stringByDeletingPathExtension]] && self.emulationViewController.rom.type == romType)
        {
            self.selectedROMIndexPath = indexPath;
            [self highlightCell:cell];
        }
        
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        cell.userInteractionEnabled = YES;
        
        cell.textLabel.textColor = UIColor.labelColor;
        cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    }
    
    cell.backgroundColor = UIColor.tertiarySystemBackgroundColor;
    cell.textLabel.backgroundColor = UIColor.clearColor;
    cell.detailTextLabel.backgroundColor = UIColor.clearColor;
    
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    return UITableViewAutomaticDimension;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    UITableViewHeaderFooterView *headerView = [self.tableView dequeueReusableHeaderFooterViewWithIdentifier:@"Header"];
    [self themeHeader:headerView];
    return headerView;
}

#pragma mark - RSTFileBrowserViewController

- (NSString *)visibleFileExtensionForIndexPath:(NSIndexPath *)indexPath
{
    NSString *extension = [[super visibleFileExtensionForIndexPath:indexPath] uppercaseString];
    
    if ([extension isEqualToString:@"GB"])
    {
        extension = @"GBC";
    }
    
    return [extension copy];
}

- (void)didRefreshCurrentDirectory
{
    [super didRefreshCurrentDirectory];
    
    if ([self isIgnoringDirectoryContentChanges])
    {
        return;
    }
    
    if ([self.supportedFiles count] == 0)
    {
        [self showNoGamesView];
    }
    else
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self hideNoGamesView];
        });
    }
    
    // Sometimes pesky invisible files remain unavailable after a download, so we filter them out
    BOOL unavailableFilesContainsVisibleFile = NO;
    
    for (NSString *filename in [self unavailableFiles])
    {
        if ([filename length] > 0 && ![[filename substringWithRange:NSMakeRange(0, 1)] isEqualToString:@"."])
        {
            unavailableFilesContainsVisibleFile = YES;
            break;
        }
    }
    
    if ([[self unavailableFiles] count] > 0 && !unavailableFilesContainsVisibleFile)
    {
        return;
    }
    
    dispatch_async(directoryContentsChangedQueue(), ^{
        
        __block NSMutableDictionary *cachedROMs = [NSMutableDictionary dictionaryWithContentsOfFile:[self cachedROMsPath]];
        
        if (cachedROMs == nil)
        {
            cachedROMs = [NSMutableDictionary dictionary];
        }
        
        for (NSString *filename in [self allFiles])
        {
            NSString *filepath = [self.currentDirectory stringByAppendingPathComponent:filename];
            
            if (([[[filename pathExtension] lowercaseString] isEqualToString:@"zip"] && ![self isDownloadingFile:filename] && ![self.unavailableFiles containsObject:filename]))
            {
                DLog(@"Unzipping.. %@", filename);
                
                NSError *error = nil;
                if (![GBAROM unzipROMAtPathToROMDirectory:filepath withPreferredROMTitle:[filename stringByDeletingPathExtension] error:&error])
                {
                    if ([error code] == NSFileWriteFileExistsError)
                    {
                        //////////////////// Same as below when importing ROM file ////////////////////
                        dispatch_async(dispatch_get_main_queue(), ^{
                            NSString *title = [NSString stringWithFormat:@"???%@??? %@", [filename stringByDeletingPathExtension], NSLocalizedString(@"Already Exists", @"")];
                            
                            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title
                                                                            message:NSLocalizedString(@"Only one copy of a game is supported at a time. To use a new version of this game, please delete the previous version and try again.", @"")
                                                                           delegate:nil
                                                                  cancelButtonTitle:NSLocalizedString(@"Dismiss", @"") otherButtonTitles:nil];
                            [alert show];
                        });
                        
                        [[NSFileManager defaultManager] removeItemAtPath:filepath error:nil];
                    }
                    else if ([error code] == NSFileReadNoSuchFileError)
                    {
                        // Too many false positives
                        /*
                        dispatch_async(dispatch_get_main_queue(), ^{
                            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Unsupported File", @"")
                                                                            message:NSLocalizedString(@"Make sure the zip file contains either a GBA or GBC ROM and try again.", @"")
                                                                           delegate:nil
                                                                  cancelButtonTitle:NSLocalizedString(@"Dismiss", @"") otherButtonTitles:nil];
                            [alert show];
                        });*/
                        
                    }
                    else if ([error code] == NSFileWriteInvalidFileNameError)
                    {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            NSString *title = [NSString stringWithFormat:@"%@ ???%@???", NSLocalizedString(@"Game Already Exists With The Name", @""), [filename stringByDeletingPathExtension]];
                            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title
                                                                            message:NSLocalizedString(@"Please rename either the existing file or the file to be imported and try again.", @"")
                                                                           delegate:nil
                                                                  cancelButtonTitle:NSLocalizedString(@"Dismiss", @"") otherButtonTitles:nil];
                            [alert show];
                        });
                        
                        [[NSFileManager defaultManager] removeItemAtPath:filepath error:nil];
                    }
                    
                    continue;
                }
                
                [[NSFileManager defaultManager] removeItemAtPath:filepath error:nil];
                
                continue;
            }
            
            if (cachedROMs[filename])
            {
                continue;
            }
            
            // VERY important this remains here, or else the hash won't be the same as the final one
            if ([self.unavailableFiles containsObject:filename] || [self isDownloadingFile:filename])
            {
                continue;
            }
            
            GBAROM *rom = [GBAROM romWithContentsOfFile:[self.currentDirectory stringByAppendingPathComponent:filename]];
            
            NSError *error = nil;
            if (![GBAROM canAddROMToROMDirectory:rom error:&error])
            {
                if ([error code] == NSFileWriteFileExistsError)
                {
                    //////////////////// Same as above when importing ROM file ////////////////////
                    dispatch_async(dispatch_get_main_queue(), ^{
                        NSString *title = [NSString stringWithFormat:@"???%@??? %@", [filename stringByDeletingPathExtension], NSLocalizedString(@"Already Exists", @"")];
                        
                        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title
                                                                        message:NSLocalizedString(@"Only one copy of a game is supported at a time. To use a new version of this game, please delete the previous version and try again.", @"")
                                                                       delegate:nil
                                                              cancelButtonTitle:NSLocalizedString(@"Dismiss", @"") otherButtonTitles:nil];
                        [alert show];
                    });
                    
                    [[NSFileManager defaultManager] removeItemAtPath:rom.filepath error:nil];
                }
                else if ([error code] == NSFileWriteInvalidFileNameError)
                {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        NSString *title = [NSString stringWithFormat:@"%@ ???%@???", NSLocalizedString(@"Game Already Exists With The Name", @""), [filename stringByDeletingPathExtension]];
                        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title
                                                                        message:NSLocalizedString(@"Please rename either the existing file or the file to be imported and try again.", @"")
                                                                       delegate:nil
                                                              cancelButtonTitle:NSLocalizedString(@"Dismiss", @"") otherButtonTitles:nil];
                        [alert show];
                    });
                    
                    [[NSFileManager defaultManager] removeItemAtPath:rom.filepath error:nil];
                }
                
                continue;
            }
            
            NSString *uniqueName = rom.uniqueName;
            
            if (uniqueName)
            {
                DLog(@"%@", uniqueName);
                
                cachedROMs[filename] = uniqueName;
                
                // New ROM, so we sync with Dropbox
                [[GBASyncManager sharedManager] synchronize];
            }
            
            [cachedROMs writeToFile:[self cachedROMsPath] atomically:YES];
            
        }
        
        // Check to see if all cached ROMs exist. If not we remove them and their syncing data.
        [[cachedROMs copy] enumerateKeysAndObjectsUsingBlock:^(NSString *filename, NSString *uniqueName, BOOL *stop) {
            
            GBAROM *rom = [GBAROM romWithContentsOfFile:[self.currentDirectory stringByAppendingPathComponent:filename]];
            
            if (rom)
            {
                return;
            }
            
            // Now check to see if the ROM exists, just under a different filename
            rom = [GBAROM romWithUniqueName:uniqueName];
            
            if (rom)
            {
                return;
            }
            
            DLog(@"Removing Files for %@...", filename);
            
            [[GBASyncManager sharedManager] deleteSyncingDataForROMWithName:[filename stringByDeletingPathExtension] uniqueName:uniqueName];
            
            // calling GBAROM romWithUniqueName will delete any invalid cachedROMs, and if we saved to disk we'd potentially overwrite other changes the romWithUniqueName method did
            //[cachedROMs removeObjectForKey:filename];
        }];
        
        
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            DLog(@"Finished inital refresh");
            [[GBASyncManager sharedManager] start];
        });
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![[NSUserDefaults standardUserDefaults] objectForKey:@"showedWarningAlert"])
            {
                WelcomeScreen *test = [[WelcomeScreen alloc] initWithNibName:@"WelcomeScreen" bundle:nil];
                [self presentViewController:test animated:true completion:nil];
            }
        });
    });
    
    
}
#pragma mark - Filepaths

- (NSString *)skinsDirectory
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    return [documentsDirectory stringByAppendingPathComponent:@"Skins"];
}

- (NSString *)GBASkinsDirectory
{
    NSFileManager *fileManager = [NSFileManager defaultManager]; // Thread-safe as of iOS 5 WOOHOO
    NSString *gbaSkinsDirectory = [[self skinsDirectory] stringByAppendingPathComponent:@"GBA"];
    
    NSError *error = nil;
    if (![fileManager createDirectoryAtPath:gbaSkinsDirectory withIntermediateDirectories:YES attributes:nil error:&error])
    {
        ELog(error);
    }
    
    return gbaSkinsDirectory;
}

- (NSString *)GBCSkinsDirectory
{
    NSFileManager *fileManager = [NSFileManager defaultManager]; // Thread-safe as of iOS 5 WOOHOO
    NSString *gbcSkinsDirectory = [[self skinsDirectory] stringByAppendingPathComponent:@"GBC"];
    
    NSError *error = nil;
    if (![fileManager createDirectoryAtPath:gbcSkinsDirectory withIntermediateDirectories:YES attributes:nil error:&error])
    {
        ELog(error);
    }
    
    return gbcSkinsDirectory;
}

- (NSString *)saveStateDirectoryForROM:(GBAROM *)rom
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    
    NSString *saveStateDirectory = [documentsDirectory stringByAppendingPathComponent:@"Save States"];
    
    return [saveStateDirectory stringByAppendingPathComponent:rom.name];
}

- (NSString *)cachedROMsPath
{
    NSString *libraryDirectory = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) lastObject];
    return [libraryDirectory stringByAppendingPathComponent:@"cachedROMs.plist"];
}

#pragma mark - Controller Skins

- (void)importDefaultSkins
{
    [self importDefaultGBASkin];
    [self importDefaultGBCSkin];
    
    [[NSUserDefaults standardUserDefaults] setObject:[NSDate date] forKey:@"updatedDefaultSkins"];
}

- (void)importDefaultGBASkin
{
    GBAControllerSkin *defaultSkin = [GBAControllerSkin defaultControllerSkinForSkinType:GBAControllerSkinTypeGBA];
    
    if (defaultSkin && [[NSUserDefaults standardUserDefaults] objectForKey:@"updatedDefaultSkins"])
    {
#if OVERWRITE_DEFAULT_SKIN
#warning Set OVERWRITE_DEFAULT_SKIN to 0 before releasing
#else
        return;
#endif
    }
    
    NSString *filepath = [[NSBundle mainBundle] pathForResource:@"Default" ofType:@"gbaskin"];
    [GBAControllerSkin extractSkinAtPathToSkinsDirectory:filepath];
}

- (void)importDefaultGBCSkin
{
    GBAControllerSkin *defaultSkin = [GBAControllerSkin defaultControllerSkinForSkinType:GBAControllerSkinTypeGBC];
    
    if (defaultSkin && [[NSUserDefaults standardUserDefaults] objectForKey:@"updatedDefaultSkins"])
    {
#if OVERWRITE_DEFAULT_SKIN
#warning Set OVERWRITE_DEFAULT_SKIN to 0 before releasing
#else
        return;
#endif
    }
    
    NSString *filepath = [[NSBundle mainBundle] pathForResource:@"Default" ofType:@"gbcskin"];
    [GBAControllerSkin extractSkinAtPathToSkinsDirectory:filepath];
}

#pragma mark - UIAlertView delegate

- (BOOL)alertViewShouldEnableFirstOtherButton:(UIAlertView *)alertView
{
    NSString *filename = [[alertView textFieldAtIndex:0] text];
    
    NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.currentDirectory error:nil];
    BOOL fileExists = NO;
    
    for (NSString *item in contents)
    {
        if ([[[item pathExtension] lowercaseString] isEqualToString:@"gba"] || [[[item pathExtension] lowercaseString] isEqualToString:@"gbc"] ||
            [[[item pathExtension] lowercaseString] isEqualToString:@"gb"] || [[[item pathExtension] lowercaseString] isEqualToString:@"zip"])
        {
            NSString *name = [item stringByDeletingPathExtension];
            
            if ([name isEqualToString:filename])
            {
                fileExists = YES;
                break;
            }
        }
    }
    
    if (fileExists)
    {
//        alertView.title = NSLocalizedString(@"File Already Exists", @"");
        alertView.title = NSLocalizedString(@"Game Name", @"");
        alertView.message = NSLocalizedString(@"File Already Exists", @"");
    }
    else
    {
        alertView.title = NSLocalizedString(@"Game Name", @"");
        alertView.message = @"";
    }
    
    return filename.length > 0 && !fileExists;
}

#pragma mark - Private

- (BOOL)isDownloadingFile:(NSString *)filename
{
    __block BOOL downloadingFile = NO;
    
    NSDictionary *dictionary = [self.currentDownloadsDictionary copy];
    
    [dictionary enumerateKeysAndObjectsUsingBlock:^(id key, NSString *downloadingFilename, BOOL *stop) {
        if ([downloadingFilename isEqualToString:filename])
        {
            downloadingFile = YES;
            *stop = YES;
        }
    }];
    
    return downloadingFile;
}

- (void)showDownloadProgressView
{
    [self.downloadProgressView setProgress:0.0];
    
    self.downloadProgress.completedUnitCount = 0;
    self.downloadProgress.totalUnitCount = 0;
    
    [UIView animateWithDuration:0.4 animations:^{
        [self.downloadProgressView setAlpha:1.0];
    }];
}

- (void)hideDownloadProgressView
{
    [UIView animateWithDuration:0.4 animations:^{
        [self.downloadProgressView setAlpha:0.0];
    } completion:^(BOOL finished) {
        self.downloadProgress.completedUnitCount = 0;
        self.downloadProgress.totalUnitCount = 0;
        [self.downloadProgressView setProgress:0.0];
    }];
}

- (void)dismissedModalViewController
{
    [self.tableView reloadData]; // Fixes incorrectly-sized cell dividers after changing orientation when a modal view controller is shown
    [self.emulationViewController refreshLayout];
}

- (void)highlightCell:(UITableViewCell *)cell
{
    UIView *backgroundView = [[UIView alloc] initWithFrame:CGRectZero];
    backgroundView.backgroundColor = UIColor.clearColor;
    
    CGFloat activeF = 10;
    CGFloat cellHeight = (cell.frame.size.height - activeF) / 2;
    CGSize textSize = [cell.textLabel.text sizeWithAttributes:@{NSFontAttributeName:[cell.textLabel font]}];
    UIView *active = [[UIView alloc] initWithFrame:CGRectMake(textSize.width + 25, cellHeight, activeF, activeF)];
    active.backgroundColor = UIColor.systemGreenColor;
    active.layer.cornerRadius = activeF / 2;
    active.layer.masksToBounds = true;
    [backgroundView addSubview:active];
    
    cell.backgroundView = backgroundView;
}


#pragma mark - No Games View

- (void)showNoGamesView
{
    UINib *noGamesViewNib = [UINib nibWithNibName:@"GBANoGamesView" bundle:nil];
    UIView *view = [[noGamesViewNib instantiateWithOwner:self options:nil] firstObject];
    
//    if (self.theme == GBAThemedTableViewControllerThemeTranslucent)
//    {
//        view.backgroundColor = [UIColor clearColor];
//
//        self.noGamesLabel.textColor = UIColor.secondaryLabelColor;
//        self.noGamesDescriptionLabel.textColor = UIColor.secondaryLabelColor;
//    }
//
    self.tableView.backgroundView = view;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.userInteractionEnabled = false;
    
    self.noGamesDescriptionLabel.preferredMaxLayoutWidth = CGRectGetWidth(self.tableView.bounds) - (29 * 2);
}

- (void)hideNoGamesView
{
    self.tableView.backgroundView = nil;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    self.tableView.userInteractionEnabled = true;
}

#pragma mark - UITableView Delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *filepath = [self filepathForIndexPath:indexPath];
    
    if ([[filepath.pathExtension lowercaseString] isEqualToString:@"zip"])
    {
        return;
    }
    
    // SET Short Cut Item with latest played game
    /*
    NSString *filename = [self filenameForIndexPath:indexPath];
    filename = [filename stringByReplacingOccurrencesOfString:@".gba" withString:@""];
    filename = [filename stringByReplacingOccurrencesOfString:@".gbc" withString:@""];
    NSLog(@"Start rom: %@", filename);
    UIApplicationShortcutIcon * photoIcon = [UIApplicationShortcutIcon iconWithTemplateImageName: @"selfie-100.png"]; // your customize icon
    UIApplication *app = [UIApplication sharedApplication];
    UIMutableApplicationShortcutItem *runGame = [[UIMutableApplicationShortcutItem alloc] initWithType:@"StartLatestRom" localizedTitle:filename localizedSubtitle:@"Last played" icon:nil userInfo:nil];
    app.shortcutItems = @[runGame];
    */
    // SET Short Cut Item with latest played game
    GBAROM *rom = [GBAROM romWithContentsOfFile:filepath];
    
    [self startROM:rom];
}


#pragma mark - Starting ROM

- (void)startROM:(GBAROM *)rom
{
    [self startROM:rom showSameROMAlertIfNeeded:YES];
}

- (void)startROM:(GBAROM *)rom showSameROMAlertIfNeeded:(BOOL)showSameROMAlertIfNeeded
{
    if ([[NSUserDefaults standardUserDefaults] boolForKey:GBASettingsDropboxSyncKey] && [DBClientsManager authorizedClient] != nil && ![[GBASyncManager sharedManager] performedInitialSync])
    {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Syncing with Dropbox", @"")
                                                        message:NSLocalizedString(@"Please wait for the initial sync to be complete, then launch the game. This is to ensure no save data is lost.", @"")
                                                       delegate:nil cancelButtonTitle:NSLocalizedString(@"Dismiss", @"") otherButtonTitles:nil];
        [alert show];
        
        [self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow] animated:YES];
        return;
    }
    
    if ([[NSUserDefaults standardUserDefaults] boolForKey:GBASettingsDropboxSyncKey] && [DBClientsManager authorizedClient] != nil && [[GBASyncManager sharedManager] isSyncing] && [[GBASyncManager sharedManager] hasPendingDownloadForROM:rom] && ![rom syncingDisabled])
    {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Syncing with Dropbox", @"")
                                                        message:NSLocalizedString(@"Data for this game is currently being downloaded. To prevent data loss, please wait until the download is complete, then launch the game.", @"")
                                                       delegate:nil
                                              cancelButtonTitle:NSLocalizedString(@"Dismiss", @"")
                                              otherButtonTitles:nil];
        [alert show];
        
        [self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow] animated:YES];
        return;
    }
    
    if ([rom newlyConflicted])
    {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Game Data is Conflicted", @"")
                                                        message:NSLocalizedString(@"Data for this game is not in sync with Dropbox, so syncing has been disabled. Please either tap View Details below to resolve the conflict manually, or ignore this message and start the game anyway. If you choose to not resolve the conflict now, you can resolve it later in the Dropbox settings.", @"")
                                                       delegate:nil
                                              cancelButtonTitle:NSLocalizedString(@"Cancel", @"")
                                              otherButtonTitles:NSLocalizedString(@"View Details", @""), NSLocalizedString(@"Start Anyway", @""), nil];
        [alert showWithSelectionHandler:^(UIAlertView *alertView, NSInteger buttonIndex) {
            if (buttonIndex == 0)
            {
                [self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow] animated:YES];
            }
            else if (buttonIndex == 1)
            {
                GBASyncingDetailViewController *syncingDetailViewController = [[GBASyncingDetailViewController alloc] initWithROM:rom];
                syncingDetailViewController.delegate = self;
                syncingDetailViewController.showDoneButton = YES;
                
                UINavigationController *navigationController = RST_CONTAIN_IN_NAVIGATION_CONTROLLER(syncingDetailViewController);
                
                if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
                {
                    navigationController.modalPresentationStyle = UIModalPresentationFormSheet;
                }
                else
                {
                    [[UIApplication sharedApplication] setStatusBarStyle:[syncingDetailViewController preferredStatusBarStyle] animated:YES];
                }
                
                [self presentViewController:navigationController animated:YES completion:nil];
                
                [rom setNewlyConflicted:NO];
            }
            else if (buttonIndex == 2)
            {
                [rom setNewlyConflicted:NO];
                
                [self startROM:rom];
            }
        }];
        
        return;
    }
        
    void(^showEmulationViewController)(void) = ^(void)
    {
        DLog(@"Unique Name: %@", rom.uniqueName);
        
        NSMutableDictionary *cachedROMs = [NSMutableDictionary dictionaryWithContentsOfFile:[self cachedROMsPath]];
        
        if (cachedROMs[[rom.filepath lastPathComponent]] == nil && rom.uniqueName)
        {
            cachedROMs[[rom.filepath lastPathComponent]] = rom.uniqueName;
            [cachedROMs writeToFile:[self cachedROMsPath] atomically:YES];
        }
                
        [[GBASyncManager sharedManager] setShouldShowSyncingStatus:NO];
        
        
        NSIndexPath *indexPath = [self.tableView indexPathForSelectedRow];
        if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone)
        {
            UIViewController *presentedViewController = [self.emulationViewController presentedViewController];
            
            if (presentedViewController == self.navigationController)
            {
                // Remove blur ourselves if we've presented a view controller, which would be opaque
                if (self.presentedViewController)
                {
                    [self.emulationViewController removeBlur];
                }
            }
        }
        
        [self.emulationViewController launchGameWithCompletion:^{
            UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
            self.selectedROMIndexPath = indexPath;
            [self highlightCell:cell];
        }];
    };
    
    if ([self.emulationViewController.rom isEqual:rom] && showSameROMAlertIfNeeded)
    {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Game already in use", @"")
                                                        message:NSLocalizedString(@"Would you like to resume where you left off, or restart the game?", @"")
                                                       delegate:nil
                                              cancelButtonTitle:NSLocalizedString(@"Cancel", @"")
                                              otherButtonTitles:NSLocalizedString(@"Resume", @""), NSLocalizedString(@"Restart", @""), nil];
        [alert showWithSelectionHandler:^(UIAlertView *alertView, NSInteger buttonIndex) {
            if (buttonIndex == 0)
            {
                [self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow] animated:YES];
            }
            else if (buttonIndex == 1)
            {
                showEmulationViewController();
            }
            else if (buttonIndex == 2)
            {
                self.emulationViewController.rom = rom;
                
                showEmulationViewController();
            }
            
        }];
    }
    else
    {
        if (showSameROMAlertIfNeeded)
        {
            self.emulationViewController.rom = rom;
        }
        
        showEmulationViewController();
    }
}

- (void)userRequestedToPlayROM:(NSNotification *)notification
{
    GBAROM *rom = notification.object;
    
    if ([self.emulationViewController.rom isEqual:rom])
    {
        [self startROM:rom showSameROMAlertIfNeeded:NO];
        return;
    }
    
    if (self.emulationViewController.rom == nil)
    {
        [self startROM:rom];
        return;
    }
    
    NSString *message = [NSString stringWithFormat:NSLocalizedString(@"Would you like to end %@ and start %@? All unsaved data will be lost.", @""), self.emulationViewController.rom.name, rom.name];
    
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Game Currently Running", @"")
                                                    message:message
                                                   delegate:nil
                                          cancelButtonTitle:NSLocalizedString(@"Cancel", @"")
                                          otherButtonTitles:NSLocalizedString(@"Start Game", @""), nil];
    [alert showWithSelectionHandler:^(UIAlertView *alert, NSInteger buttonIndex) {
        if (buttonIndex == 1)
        {
            [self startROM:rom];
        }
        else
        {
            if (self.presentedViewController == nil)
            {
                [self.emulationViewController resumeEmulation];
            }
        }
    }];
    
    [self.emulationViewController pauseEmulation];
}

- (void)syncingDetailViewControllerDidDismiss:(GBASyncingDetailViewController *)syncingDetailViewController
{
    if (![syncingDetailViewController.rom syncingDisabled] && !([[GBASyncManager sharedManager] isSyncing] && [[GBASyncManager sharedManager] hasPendingDownloadForROM:syncingDetailViewController.rom]))
    {
        [self startROM:syncingDetailViewController.rom];
    }
    else
    {
        [self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow] animated:YES];
    }
}

#pragma mark - GBASplitViewControllerEmulationDelegate

- (BOOL)splitViewControllerShouldResumeEmulation:(GBASplitViewController *)splitViewController
{
    if (self.emulationViewController.rom == nil)
    {
        return NO;
    }
    
    [self startROM:self.emulationViewController.rom showSameROMAlertIfNeeded:NO];
    
    // Always return NO, because we'll resume the emulation ourselves
    return NO;
}

#pragma mark - Deleting/Renaming/Sharing

- (void)didDetectLongPressGesture:(UILongPressGestureRecognizer *)gestureRecognizer
{
    if (gestureRecognizer.state != UIGestureRecognizerStateBegan)
    {
        return;
    }
    
    UITableViewCell *cell = (UITableViewCell *)[gestureRecognizer view];
    NSIndexPath *indexPath = [self.tableView indexPathForCell:cell];
    
    CGRect rect = [self.tableView rectForRowAtIndexPath:indexPath];
    
    if ([UIAlertController class])
    {
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
        
        [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"") style:UIAlertActionStyleCancel handler:nil]];
        [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Rename Game", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self showRenameAlertForROMAtIndexPath:indexPath];
        }]];
        [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Share Game", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self shareROMAtIndexPath:indexPath];
        }]];
        
        UIPopoverPresentationController *presentationController = [alertController popoverPresentationController];
        presentationController.permittedArrowDirections = UIPopoverArrowDirectionAny;
        presentationController.sourceView = self.splitViewController.view;
        presentationController.sourceRect = [self.splitViewController.view convertRect:rect fromView:self.tableView];
        
        [self presentViewController:alertController animated:YES completion:nil];
    }
    else
    {
        UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:nil
                                                                 delegate:nil
                                                        cancelButtonTitle:NSLocalizedString(@"Cancel", @"")
                                                   destructiveButtonTitle:nil
                                                        otherButtonTitles:NSLocalizedString(@"Rename Game", @""), NSLocalizedString(@"Share Game", @""), nil];
        UIView *presentationView = self.view;
        
        if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
        {
            presentationView = self.splitViewController.view;
            rect = [presentationView convertRect:rect fromView:self.tableView];
        }
        
        [actionSheet showFromRect:rect inView:presentationView animated:YES selectionHandler:^(UIActionSheet *actionSheet, NSInteger buttonIndex) {
            if (buttonIndex == 0)
            {
                [self showRenameAlertForROMAtIndexPath:indexPath];
            }
            else if (buttonIndex == 1)
            {
                [self shareROMAtIndexPath:indexPath];
            }
        }];
    }
}

- (void)deleteForAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *title = NSLocalizedString(@"Are you sure you want to delete this game and all of its saved data?", nil);
    
    if ([[NSUserDefaults standardUserDefaults] boolForKey:GBASettingsDropboxSyncKey])
    {
        title = [title stringByAppendingFormat:@" Your data in Dropbox will not be affected."];
    }
    
    CGRect rect = [self.tableView rectForRowAtIndexPath:indexPath];
    
    if ([UIAlertController class])
    {
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleActionSheet];
        [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"") style:UIAlertActionStyleCancel handler:nil]];
        [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Delete Game and Data", @"") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            [self deleteROMAtIndexPath:indexPath];
        }]];
        
        UIPopoverPresentationController *presentationController = [alertController popoverPresentationController];
        presentationController.permittedArrowDirections = UIPopoverArrowDirectionAny;
        presentationController.sourceView = self.splitViewController.view;
        presentationController.sourceRect = [self.splitViewController.view convertRect:rect fromView:self.tableView];
        
        [self presentViewController:alertController animated:YES completion:nil];
    }
    else
    {
        UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:title
                                                                 delegate:nil
                                                        cancelButtonTitle:NSLocalizedString(@"Cancel", @"")
                                                   destructiveButtonTitle:NSLocalizedString(@"Delete Game and Data", nil)
                                                        otherButtonTitles:nil];
        
        UIView *presentationView = self.view;
        
        if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
        {
            presentationView = self.splitViewController.view;
            rect = [presentationView convertRect:rect fromView:self.tableView];
        }
        
        [actionSheet showFromRect:rect inView:presentationView animated:YES selectionHandler:^(UIActionSheet *actionSheet, NSInteger buttonIndex) {
            
            if (buttonIndex == 0)
            {
                [self deleteROMAtIndexPath:indexPath];
            }
        }];
    }
}

- (void)showRenameAlertForROMAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *filepath = [self filepathForIndexPath:indexPath];
    NSString *romName = [[filepath lastPathComponent] stringByDeletingPathExtension];
    
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Rename Game", @"") message:nil delegate:self cancelButtonTitle:NSLocalizedString(@"Cancel", @"") otherButtonTitles:NSLocalizedString(@"Rename", @""), nil];
    alert.alertViewStyle = UIAlertViewStylePlainTextInput;
    
    UITextField *textField = [alert textFieldAtIndex:0];
    textField.text = romName;
    textField.autocapitalizationType = UITextAutocapitalizationTypeWords;
    
    [alert showWithSelectionHandler:^(UIAlertView *alertView, NSInteger buttonIndex) {
        if (buttonIndex == 1)
        {
            UITextField *textField = [alertView textFieldAtIndex:0];
            [self renameROMAtIndexPath:indexPath toName:textField.text];
        }
    }];
}

- (void)deleteROMAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *filepath = [self filepathForIndexPath:indexPath];
    NSString *romName = [[filepath lastPathComponent] stringByDeletingPathExtension];
    
    GBAROM *rom = [GBAROM romWithContentsOfFile:filepath];
    
    
    NSString *saveFile = [NSString stringWithFormat:@"%@.sav", romName];
    NSString *rtcFile = [NSString stringWithFormat:@"%@.rtc", romName];
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    
    NSString *romUniqueName = rom.uniqueName;
    
    if (rom.name == nil || [rom.name isEqualToString:@""] || [rom.name isEqualToString:@"/"])
    {
        // Do NOT make this string @"", or else it'll then delete the entire cheats/save states folder
        romUniqueName = @"Unknown";
    }
    
    NSString *cheatsParentDirectory = [documentsDirectory stringByAppendingPathComponent:@"Cheats"];
    NSString *cheatsDirectory = [cheatsParentDirectory stringByAppendingPathComponent:rom.name];
    
    NSString *saveStateParentDirectory = [documentsDirectory stringByAppendingPathComponent:@"Save States"];
    NSString *saveStateDirectory = [saveStateParentDirectory stringByAppendingPathComponent:rom.name];
        
    // Handled by deletedFileAtIndexPath
    //[[NSFileManager defaultManager] removeItemAtPath:filepath error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:[documentsDirectory stringByAppendingPathComponent:saveFile] error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:[documentsDirectory stringByAppendingPathComponent:rtcFile] error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:saveStateDirectory error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:cheatsDirectory error:nil];
    
    NSMutableDictionary *cachedROMs = [NSMutableDictionary dictionaryWithContentsOfFile:[self cachedROMsPath]];
    [cachedROMs removeObjectForKey:romName];
    [cachedROMs writeToFile:[self cachedROMsPath] atomically:YES];
        
    [self deleteFileAtIndexPath:indexPath animated:YES];
    
    [[GBASyncManager sharedManager] deleteSyncingDataForROMWithName:romName uniqueName:romUniqueName];
}

- (void)renameROMAtIndexPath:(NSIndexPath *)indexPath toName:(NSString *)newName
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    
    NSString *filepath = [self filepathForIndexPath:indexPath];
    NSString *extension = [filepath pathExtension];
    
    // Must go before the actual name change
    GBAROM *rom = [GBAROM romWithContentsOfFile:filepath];
    [rom renameToName:newName];
    
    // ROM
    NSString *romName = [[filepath lastPathComponent] stringByDeletingPathExtension];
    NSString *newRomFilename = [NSString stringWithFormat:@"%@.%@", newName, extension]; // Includes extension
    
    // Save File
    NSString *saveFile = [NSString stringWithFormat:@"%@.sav", romName];
    NSString *newSaveFile = [NSString stringWithFormat:@"%@.sav", newName];
    
    // RTC file
    NSString *rtcFile = [NSString stringWithFormat:@"%@.rtc", romName];
    NSString *newRTCFile = [NSString stringWithFormat:@"%@.rtc", newName];
    
    // Cheats
    NSString *cheatsParentDirectory = [documentsDirectory stringByAppendingPathComponent:@"Cheats"];
    NSString *cheatsDirectory = [cheatsParentDirectory stringByAppendingPathComponent:romName];
    NSString *newCheatsDirectory = [cheatsParentDirectory stringByAppendingPathComponent:newName];
    
    // Save States
    NSString *saveStateParentDirectory = [documentsDirectory stringByAppendingPathComponent:@"Save States"];
    NSString *saveStateDirectory = [saveStateParentDirectory stringByAppendingPathComponent:romName];
    NSString *newSaveStateDirectory = [saveStateParentDirectory stringByAppendingPathComponent:newName];
    
    [self setIgnoreDirectoryContentChanges:YES];
    
    [[NSFileManager defaultManager] moveItemAtPath:filepath toPath:[documentsDirectory stringByAppendingPathComponent:newRomFilename] replaceExistingFile:YES error:nil];
    [[NSFileManager defaultManager] moveItemAtPath:[documentsDirectory stringByAppendingPathComponent:saveFile] toPath:[documentsDirectory stringByAppendingPathComponent:newSaveFile] replaceExistingFile:YES error:nil];
    [[NSFileManager defaultManager] moveItemAtPath:[documentsDirectory stringByAppendingPathComponent:rtcFile] toPath:[documentsDirectory stringByAppendingPathComponent:newRTCFile] replaceExistingFile:YES error:nil];
    [[NSFileManager defaultManager] moveItemAtPath:cheatsDirectory toPath:newCheatsDirectory replaceExistingFile:YES error:nil];
    [[NSFileManager defaultManager] moveItemAtPath:saveStateDirectory toPath:newSaveStateDirectory replaceExistingFile:YES error:nil];
    
    [self setIgnoreDirectoryContentChanges:NO];
    
    NSMutableDictionary *cachedROMs = [NSMutableDictionary dictionaryWithContentsOfFile:[self cachedROMsPath]];
    [cachedROMs setObject:rom.uniqueName forKey:newRomFilename];
    [cachedROMs removeObjectForKey:[filepath lastPathComponent]];
    [cachedROMs writeToFile:[self cachedROMsPath] atomically:YES];
}

- (void)shareROMAtIndexPath:(NSIndexPath *)indexPath
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    
    NSString *romFilepath = [self filepathForIndexPath:indexPath];
    NSString *romName = [[romFilepath lastPathComponent] stringByDeletingPathExtension];
    NSURL *romFileURL = [NSURL fileURLWithPath:romFilepath];
    
    UIActivityViewController *activityViewController = nil;
    
    if (NSFoundationVersionNumber <= NSFoundationVersionNumber_iOS_7_0)
    {
        activityViewController = [[UIActivityViewController alloc] initWithActivityItems:@[romFileURL] applicationActivities:@[[GBAMailActivity new]]];
        activityViewController.excludedActivityTypes = @[UIActivityTypeMessage, UIActivityTypeMail]; // Can't install from Messages app, and we use our own Mail activity that supports custom file types
    }
    else
    {
        activityViewController = [[UIActivityViewController alloc] initWithActivityItems:@[romFileURL] applicationActivities:nil];
        activityViewController.excludedActivityTypes = @[UIActivityTypeMessage];
    }
    
    CGRect rect = [self.tableView rectForRowAtIndexPath:indexPath];
    rect = [self.splitViewController.view convertRect:rect fromView:self.tableView];
    
    if ([UIAlertController class])
    {
        activityViewController.modalPresentationStyle = UIModalPresentationPopover;
        
        UIPopoverPresentationController *presentationController = [activityViewController popoverPresentationController];
        presentationController.permittedArrowDirections = UIPopoverArrowDirectionAny;
        presentationController.sourceView = self.splitViewController.view;
        presentationController.sourceRect = rect;
        
        [self presentViewController:activityViewController animated:YES completion:nil];
    }
    else
    {
        if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone)
        {
            [self presentViewController:activityViewController animated:YES completion:NULL];
        }
        else
        {
            self.activityPopoverController = [[UIPopoverController alloc] initWithContentViewController:activityViewController];
            self.activityPopoverController.delegate = self;
            [self.activityPopoverController presentPopoverFromRect:rect inView:self.splitViewController.view permittedArrowDirections:UIPopoverArrowDirectionLeft animated:YES];
        }
    }
}

#pragma mark - UIPopoverController delegate

- (void)popoverControllerDidDismissPopover:(UIPopoverController *)popoverController
{
    self.activityPopoverController = nil;
}

#pragma mark - IBActions

- (IBAction)presentSettings:(UIBarButtonItem *)barButtonItem
{
    GBASettingsViewController *settingsViewController = [[GBASettingsViewController alloc] init];
    settingsViewController.delegate = self;
    
    [[UIApplication sharedApplication] setStatusBarStyle:[settingsViewController preferredStatusBarStyle] animated:YES];
    
    UINavigationController *navigationController = RST_CONTAIN_IN_NAVIGATION_CONTROLLER(settingsViewController);
    
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
    {
        navigationController.modalPresentationStyle = UIModalPresentationFormSheet;
    }
    [self presentViewController:navigationController animated:YES completion:NULL];
}

#pragma mark - Settings

- (void)settingsDidChange:(NSNotification *)notification
{
    if ([notification.userInfo[@"key"] isEqualToString:GBASettingsRememberLastWebpageKey])
    {
        
    }
}

- (void)settingsViewControllerWillDismiss:(GBASettingsViewController *)settingsViewController
{
    [self dismissedModalViewController];
}

#pragma mark - Getters/Setters

- (void)setRomType:(GBAVisibleROMType)romType
{
//    self.romTypeSegmentedControl.selectedSegmentIndex = romType;
    
    [[NSUserDefaults standardUserDefaults] setInteger:romType forKey:@"romType"];
    
    switch (romType) {
        case GBAVisibleROMTypeAll:
            self.supportedFileExtensions = @[@"gba", @"gbc", @"gb", @"zip"];
            [self setupFilterMenu:@"all"];
            break;
            
        case GBAVisibleROMTypeGBA:
            self.supportedFileExtensions = @[@"gba", @"gba"];
            [self setupFilterMenu:@"gba"];
            break;
            
        case GBAVisibleROMTypeGBC:
            self.supportedFileExtensions = @[@"gb", @"gbc", @"gbc"];
            [self setupFilterMenu:@"gbc"];
            break;
    }
    
    _visibleRomType = romType;
}

- (void)setTheme:(GBAThemedTableViewControllerTheme)theme
{
    // Navigation controller is different each time, so we need to update theme every time we present this view controller
    /*if (_theme == theme)
    {
        return;
    }*/
    
    _theme = theme;
    
    [self updateTheme];
    
    self.downloadProgressView.frame = CGRectMake(0,
                                                 CGRectGetHeight(self.navigationController.navigationBar.bounds) - CGRectGetHeight(self.downloadProgressView.bounds),
                                                 CGRectGetWidth(self.navigationController.navigationBar.bounds),
                                                 CGRectGetHeight(self.downloadProgressView.bounds));
    [self.navigationController.navigationBar addSubview:self.downloadProgressView];
}

@end
