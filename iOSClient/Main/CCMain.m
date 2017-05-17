//
//  CCMain.m
//  Crypto Cloud Technology Nextcloud
//
//  Created by Marino Faggiana on 04/09/14.
//  Copyright (c) 2017 TWS. All rights reserved.
//
//  Author Marino Faggiana <m.faggiana@twsweb.it>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

#import "CCMain.h"
#import "AppDelegate.h"
#import "CCPhotosCameraUpload.h"
#import "CCSynchronize.h"
#import "CCTransfersCell.h"
#import "OCActivity.h"
#import "OCNotifications.h"
#import "OCNotificationsAction.h"
#import "OCFrameworkConstants.h"
#import "OCCapabilities.h"
#import "CTAssetCheckmark.h"
#import "NCBridgeSwift.h"

#define alertCreateFolder 1
#define alertCreateFolderCrypto 2
#define alertRename 3
#define alertOfflineFolder 4

@interface CCMain () <CCActionsDeleteDelegate, CCActionsRenameDelegate, CCActionsSearchDelegate, CCActionsDownloadThumbnailDelegate, CCActionsSettingFavoriteDelegate>
{
    CCMetadata *_metadata;
        
    BOOL _isRoot;
    BOOL _isViewDidLoad;
    BOOL _isOfflineServerUrl;
    
    BOOL _isPickerCriptate;              // if is cryptated image or video back from picker
    BOOL _isSelectedMode;
        
    NSMutableArray *_selectedMetadatas;
    NSMutableArray *_queueSelector;
    NSUInteger _numSelectedMetadatas;
    UIImageView *_ImageTitleHomeCryptoCloud;
    UIView *_reMenuBackgroundView;
    UITapGestureRecognizer *_singleFingerTap;
    
    NSString *_directoryGroupBy;
    NSString *_directoryOrder;
    
    NSUInteger _failedAttempts;
    NSDate *_lockUntilDate;

    NSString *_fatherPermission;

    UIRefreshControl *_refreshControl;
    UIDocumentInteractionController *_docController;

    CCHud *_hud;
    CCHud *_hudDeterminate;
    
    // Datasource
    CCSectionDataSourceMetadata *_sectionDataSource;
    NSDate *_dateReadDataSource;
    
    // Search
    BOOL _isSearchMode;
    NSString *_searchFileName;
    NSMutableArray *_searchResultMetadatas;
    NSString *_depth;
    NSString *_noFilesSearchTitle;
    NSString *_noFilesSearchDescription;
    
    // Login
    CCLoginWeb *_loginWeb;
    CCLogin *_loginVC;
}
@end

@implementation CCMain

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Init =====
#pragma --------------------------------------------------------------------------------------------

-  (id)initWithCoder:(NSCoder *)aDecoder
{    
    if (self = [super initWithCoder:aDecoder])  {
        
        _directoryOrder = [CCUtility getOrderSettings];
        _directoryGroupBy = [CCUtility getGroupBySettings];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(initializeMain:) name:@"initializeMain" object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(clearDateReadDataSource:) name:@"clearDateReadDataSource" object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(setTitle) name:@"setTitleMain" object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(triggerProgressTask:) name:@"NotificationProgressTask" object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(changeTheming) name:@"changeTheming" object:nil];
    }
    
    return self;
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== View =====
#pragma --------------------------------------------------------------------------------------------

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    // init object
    _metadata = [CCMetadata new];
    _hud = [[CCHud alloc] initWithView:[[[UIApplication sharedApplication] delegate] window]];
    _hudDeterminate = [[CCHud alloc] initWithView:[[[UIApplication sharedApplication] delegate] window]];
    _selectedMetadatas = [NSMutableArray new];
    _queueSelector = [NSMutableArray new];
    _isViewDidLoad = YES;
    _fatherPermission = @"";
    _searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    _searchResultMetadatas = [NSMutableArray new];
    _searchFileName = @"";
    _depth = @"0";
    _noFilesSearchTitle = @"";
    _noFilesSearchDescription = @"";
    
    // delegate
    self.tableView.delegate = self;
    self.tableView.tableFooterView = [UIView new];
    self.tableView.separatorColor = [NCBrandColor sharedInstance].seperator;
    self.tableView.emptyDataSetDelegate = self;
    self.tableView.emptyDataSetSource = self;
    self.searchController.delegate = self;
    self.searchController.searchBar.delegate = self;
    
    [[CCNetworking sharedNetworking] settingDelegate:self];
    
    // Custom Cell
    [self.tableView registerNib:[UINib nibWithNibName:@"CCCellMain" bundle:nil] forCellReuseIdentifier:@"CellMain"];
    [self.tableView registerNib:[UINib nibWithNibName:@"CCCellMainTransfer" bundle:nil] forCellReuseIdentifier:@"CellMainTransfer"];
    
    // long press recognizer TableView
    UILongPressGestureRecognizer* longPressRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(onLongPressTableView:)];
    [self.tableView addGestureRecognizer:longPressRecognizer];
    
    // Pull-to-Refresh
    [self createRefreshControl];
    
    // Register for 3D Touch Previewing if available
    if ([self.traitCollection respondsToSelector:@selector(forceTouchCapability)] && (self.traitCollection.forceTouchCapability == UIForceTouchCapabilityAvailable))
    {
        [self registerForPreviewingWithDelegate:self sourceView:self.view];
    }

    // Back Button
    if ([_serverUrl isEqualToString:[CCUtility getHomeServerUrlActiveUrl:app.activeUrl]])
        self.navigationItem.backBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"navigationLogo"] style:UIBarButtonItemStylePlain target:nil action:nil];
    
    // reMenu Background
    _reMenuBackgroundView = [[UIView alloc] init];
    _reMenuBackgroundView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
    
    // if this is not Main (the Main uses inizializeMain)
    if (_isRoot == NO && app.activeAccount.length > 0) {
        
        // Settings this folder & delegate & Loading datasource
        app.directoryUser = [CCUtility getDirectoryActiveUser:app.activeUser activeUrl:app.activeUrl];
        
        // Load Datasource
        [self reloadDatasource:_serverUrl fileID:nil selector:nil];
        
        // Read Folder
        [self readFolderWithForced:NO serverUrl:_serverUrl];
    }
    
    // Title
    [self setTitle];
    
    // Search
    self.definesPresentationContext = YES;
    self.searchController.searchResultsUpdater = self;
    self.searchController.dimsBackgroundDuringPresentation = NO;
    self.tableView.tableHeaderView = self.searchController.searchBar;
    self.searchController.searchBar.barTintColor = [NCBrandColor sharedInstance].seperator;
    [self.searchController.searchBar sizeToFit];
    self.searchController.searchBar.delegate = self;
    self.searchController.searchBar.placeholder = NSLocalizedString(@"_search_this_folder_",nil);
    
    if ([[NCManageDatabase sharedInstance] getServerVersionAccount:app.activeAccount] >= 12) {
        
        if (_isRoot)
            self.searchController.searchBar.scopeButtonTitles = [NSArray arrayWithObjects:NSLocalizedString(@"_search_this_folder_",nil),NSLocalizedString(@"_search_all_folders_",nil), nil];
        else
            self.searchController.searchBar.scopeButtonTitles = [NSArray arrayWithObjects:NSLocalizedString(@"_search_this_folder_",nil),NSLocalizedString(@"_search_sub_folder_",nil), nil];
    } else {
        
        self.searchController.searchBar.scopeButtonTitles = nil;
    }
    
    // Hide Search Filed on Load
    [self.tableView setContentOffset:CGPointMake(0, self.searchController.searchBar.frame.size.height - self.tableView.contentOffset.y)];
}

// Apparirà
- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    // test
    if (app.activeAccount.length == 0)
        return;
    
    // Settings this folder & delegate & Loading datasource
    app.directoryUser = [CCUtility getDirectoryActiveUser:app.activeUser activeUrl:app.activeUrl];
    
    [[CCNetworking sharedNetworking] settingDelegate:self];
    
    // Color
    [app aspectNavigationControllerBar:self.navigationController.navigationBar encrypted:_isFolderEncrypted online:[app.reachability isReachable] hidden:NO];
    [app aspectTabBar:self.tabBarController.tabBar hidden:NO];
    
    if (_isSelectedMode)
        [self setUINavigationBarSelected];
    else
        [self setUINavigationBarDefault];
    
    // Plus Button
    [app plusButtonVisibile:true];
}

// E' arrivato
- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    // Active Main
    app.activeMain = self;
    
    // Test viewDidLoad
    if (_isViewDidLoad) {
        
        _isViewDidLoad = NO;
        
    } else {
        
        if (app.activeAccount.length > 0) {
            
            // Load Datasource
            [self reloadDatasource:_serverUrl fileID:nil selector:nil];
            
            // Read Folder
            [self readFolderWithForced:NO serverUrl:_serverUrl];
        }
    }

    // Title
    [self setTitle];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    [self closeAllMenu];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.    
}

- (BOOL)prefersStatusBarHidden
{
    return NO;
}

// detect scroll for remove keyboard in search mode
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
    if (_isSearchMode && scrollView == self.tableView) {
        
        [self.searchController.searchBar endEditing:YES];
    }
}

- (void)changeTheming
{
    if (self.isViewLoaded && self.view.window)
        [app changeTheming:self];
    
    // Refresh control
    _refreshControl.tintColor = [NCBrandColor sharedInstance].brand;
    
    // Reload Table View
    [self.tableView reloadData];
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Initizlize Mail =====
#pragma --------------------------------------------------------------------------------------------

- (void)initializeMain:(NSNotification *)notification
{
    _directoryGroupBy = nil;
    _directoryOrder = nil;
    _dateReadDataSource = nil;
    
    // test
    if (app.activeAccount.length == 0)
        return;
    
    if ([app.listMainVC count] == 0 || _isRoot) {
        
        // This is Root
        _isRoot = YES;
        
        // Crypto Mode
        if ([[CCUtility getKeyChainPasscodeForUUID:[CCUtility getUUID]] length] == 0) {
           
            app.isCryptoCloudMode = NO;
            
        } else {
         
            app.isCryptoCloudMode = YES;
        }
        
        // go Home
        [self.navigationController popToRootViewControllerAnimated:NO];
        
        // Remove search mode
        [self cancelSearchBar];
        
        _serverUrl = [CCUtility getHomeServerUrlActiveUrl:app.activeUrl];
        _isFolderEncrypted = NO;
        
        app.directoryUser = [CCUtility getDirectoryActiveUser:app.activeUser activeUrl:app.activeUrl];
    
        // add list
        [app.listMainVC setObject:self forKey:_serverUrl];
    
        // setting Networking
        [[CCNetworking sharedNetworking] settingDelegate:self];
        [[CCNetworking sharedNetworking] settingAccount];
        
        // populate shared Link & User variable
        
        NSArray *results = [[NCManageDatabase sharedInstance] getSharesAccount:app.activeAccount];
        app.sharesLink = results[0];
        app.sharesUserAndGroup = results[1];
        
        // Setting Theming
        [app settingThemingColorBrand];
        
        // Load Datasource
        [self reloadDatasource:_serverUrl fileID:nil selector:nil];

        // Load Folder
        [self readFolderWithForced:NO serverUrl:_serverUrl];
        
        // Load photo datasorce
        if (app.activePhotosCameraUpload)
            [app.activePhotosCameraUpload reloadDatasourceForced];
        
        // remove all of detail
        if (app.activeDetail)
            [app.activeDetail removeAllView];
        
        // remove all Notification Messages
        [app.listOfNotifications removeAllObjects];
        
        // home main
        app.homeMain = self;
        
        // Initializations
        [app applicationInitialized];
                
    } else {
        
        // reload datasource
        [self reloadDatasource:_serverUrl fileID:nil selector:nil];
    }
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ==== DZNEmptyDataSetSource ====
#pragma --------------------------------------------------------------------------------------------

/*
- (BOOL)emptyDataSetShouldDisplay:(UIScrollView *)scrollView
{
    if(_isSearchMode)
        return NO;
    else
        return YES;
}
*/

- (BOOL)emptyDataSetShouldAllowScroll:(UIScrollView *)scrollView
{
    return YES;
}

- (UIColor *)backgroundColorForEmptyDataSet:(UIScrollView *)scrollView
{
    return [UIColor whiteColor];
}

- (UIImage *)imageForEmptyDataSet:(UIScrollView *)scrollView
{
    if (_isSearchMode)
        return [UIImage imageNamed:@"searchBig"];
    else
        return [CCGraphics changeThemingColorImage:[UIImage imageNamed:@"filesNoFiles"] color:[NCBrandColor sharedInstance].brand];
}

- (NSAttributedString *)titleForEmptyDataSet:(UIScrollView *)scrollView
{
    NSString *text;
    
    if (_isSearchMode)
        text = _noFilesSearchTitle;
    else
        text = [NSString stringWithFormat:@"%@", NSLocalizedString(@"_files_no_files_", nil)];
    
    NSDictionary *attributes = @{NSFontAttributeName:[UIFont boldSystemFontOfSize:20.0f], NSForegroundColorAttributeName:[UIColor lightGrayColor]};
    
    return [[NSAttributedString alloc] initWithString:text attributes:attributes];
}

- (NSAttributedString *)descriptionForEmptyDataSet:(UIScrollView *)scrollView
{
    NSString *text;
    
    if (_isSearchMode)
        text = _noFilesSearchDescription;
    else
        text = [NSString stringWithFormat:@"\n%@", NSLocalizedString(@"_no_file_pull_down_", nil)];
    
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.lineBreakMode = NSLineBreakByWordWrapping;
    paragraph.alignment = NSTextAlignmentCenter;
    
    NSDictionary *attributes = @{NSFontAttributeName: [UIFont systemFontOfSize:14.0], NSForegroundColorAttributeName: [UIColor lightGrayColor], NSParagraphStyleAttributeName: paragraph};
    
    return [[NSAttributedString alloc] initWithString:text attributes:attributes];
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== AlertView =====
#pragma --------------------------------------------------------------------------------------------

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    [alertView dismissWithClickedButtonIndex:buttonIndex animated:YES];
        
    if (alertView.tag == alertCreateFolder && buttonIndex == 1) [self createFolder:[alertView textFieldAtIndex:0].text folderCameraUpload:NO];
    
    if (alertView.tag == alertCreateFolderCrypto && buttonIndex == 1) [self createFolderEncrypted:[alertView textFieldAtIndex:0].text];
    
    if (alertView.tag == alertRename && buttonIndex == 1) {
     
        if ([_metadata.model isEqualToString:@"note"]) {
        
            [self renameNote:_metadata fileName:[alertView textFieldAtIndex:0].text];
            
        } else {
            
            [self renameFile:_metadata fileName:[alertView textFieldAtIndex:0].text];
        }
    }
    if (alertView.tag == alertOfflineFolder && buttonIndex == 1) {
        
        NSString *serverUrl = [CCCoreData getServerUrlFromDirectoryID:_metadata.directoryID activeAccount:_metadata.account];

        NSString *dir = [CCUtility stringAppendServerUrl:serverUrl addFileName:_metadata.fileNameData];
        
        [[CCSynchronize sharedSynchronize] addOfflineFolder:dir];
        
        [self performSelector:@selector(reloadDatasource) withObject:nil];
    }
}

// accept only number char > 0
- (BOOL)alertViewShouldEnableFirstOtherButton:(UIAlertView *)alertView
{
    /* Retrieve a text field at an index -
     raises NSRangeException when textFieldIndex is out-of-bounds.
     
     The field at index 0 will be the first text field
     (the single field or the login field),
     
     The field at index 1 will be the password field. */
    
    /*
     1> Get the Text Field in alertview
     
     2> Get the text of that Text Field
     
     3> Verify that text length
     
     4> return YES or NO Based on the length
     */
    
    if (alertView.tag == alertOfflineFolder) return YES;
    else return ([[[alertView textFieldAtIndex:0] text] length]>0)?YES:NO;
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Graphic Window =====
#pragma --------------------------------------------------------------------------------------------

- (void)createRefreshControl
{
    _refreshControl = [UIRefreshControl new];
    _refreshControl.tintColor = [NCBrandColor sharedInstance].brand;
    _refreshControl.backgroundColor = [UIColor colorWithRed:235.0/255.0 green:235.0/255.0 blue:235.0/255.0 alpha:1.0];
    [_refreshControl addTarget:self action:@selector(refreshControlTarget) forControlEvents:UIControlEventValueChanged];
    [self setRefreshControl:_refreshControl];
}

- (void)deleteRefreshControl
{
    [_refreshControl endRefreshing];
    self.refreshControl = nil;
}

- (void)refreshControlTarget
{
    [self readFolderWithForced:YES serverUrl:_serverUrl];
    
    // Actuate `Peek` feedback (weak boom)
    AudioServicesPlaySystemSound(1519);
    
    [_ImageTitleHomeCryptoCloud setUserInteractionEnabled:NO];
}

- (void)setTitle
{
    // Color text self.navigationItem.title
    [app aspectNavigationControllerBar:self.navigationController.navigationBar encrypted:_isFolderEncrypted online:[app.reachability isReachable] hidden:NO];

    if (_isSelectedMode) {
        
        NSUInteger totali = [_sectionDataSource.allRecordsDataSource count];
        NSUInteger selezionati = [[self.tableView indexPathsForSelectedRows] count];
        
        self.navigationItem.titleView = nil;
        self.navigationItem.title = [NSString stringWithFormat:@"%@ : %lu / %lu", NSLocalizedString(@"_selected_", nil), (unsigned long)selezionati, (unsigned long)totali];

    } else {
        
        // we are in home : LOGO BRAND
        if ([_serverUrl isEqualToString:[CCUtility getHomeServerUrlActiveUrl:app.activeUrl]]) {
            
            self.navigationItem.title = nil;
            
            if ([app.reachability isReachable] == NO)
                _ImageTitleHomeCryptoCloud = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"navigationLogoOffline"]];
            else
                _ImageTitleHomeCryptoCloud = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"navigationLogo"]];
            
            [_ImageTitleHomeCryptoCloud setUserInteractionEnabled:YES];
            UITapGestureRecognizer *singleTap =  [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(menuLogo)];
            [singleTap setNumberOfTapsRequired:1];
            [_ImageTitleHomeCryptoCloud addGestureRecognizer:singleTap];
            
            self.navigationItem.titleView = _ImageTitleHomeCryptoCloud;
            
        } else {
        
            self.navigationItem.title = _titleMain;
        }
    }
}

- (void)setUINavigationBarDefault
{
    [app aspectNavigationControllerBar:self.navigationController.navigationBar encrypted:_isFolderEncrypted online:[app.reachability isReachable] hidden:NO];
    
    UIBarButtonItem *buttonMore, *buttonNotification;
    
    // =
    buttonMore = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"navigationControllerMenu"] style:UIBarButtonItemStylePlain target:self action:@selector(toggleReMainMenu)];
    buttonMore.enabled = true;
    
    // <
    self.navigationController.navigationBar.hidden = NO;
    
    // Notification
    if ([app.listOfNotifications count] > 0) {
        
        buttonNotification = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"notification"] style:UIBarButtonItemStylePlain target:self action:@selector(viewNotification)];
        buttonNotification.tintColor = [NCBrandColor sharedInstance].navigationBarText;
        buttonNotification.enabled = true;
    }
    
    if (buttonNotification)
        self.navigationItem.rightBarButtonItems = [[NSArray alloc] initWithObjects:buttonMore, buttonNotification, nil];
    else
        self.navigationItem.rightBarButtonItems = [[NSArray alloc] initWithObjects:buttonMore, nil];

    self.navigationItem.leftBarButtonItem = nil;
}

- (void)setUINavigationBarSelected
{
    [app aspectNavigationControllerBar:self.navigationController.navigationBar encrypted:_isFolderEncrypted online:[app.reachability isReachable] hidden:NO];
    
    UIImage *icon = [UIImage imageNamed:@"navigationControllerMenu"];
    UIBarButtonItem *buttonMore = [[UIBarButtonItem alloc] initWithImage:icon style:UIBarButtonItemStylePlain target:self action:@selector(toggleReSelectMenu)];

    UIBarButtonItem *leftButton = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"_cancel_", nil) style:UIBarButtonItemStylePlain target:self action:@selector(cancelSelect)];
    
    self.navigationItem.leftBarButtonItem = leftButton;
    self.navigationItem.rightBarButtonItems = [[NSArray alloc] initWithObjects:buttonMore, nil];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    [self closeAllMenu];
    
    [coordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        
    }];
    
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
}

- (void)cancelSelect
{
    [self tableViewSelect:NO];
    [app.reSelectMenu close];
}

- (void)closeAllMenu
{
    // close Menu
    [app.reSelectMenu close];
    [app.reMainMenu close];
    
    // Close Menu Logo
    [CCMenuAccount dismissMenu];
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Document Picker =====
#pragma --------------------------------------------------------------------------------------------

- (void)documentMenuWasCancelled:(UIDocumentMenuViewController *)documentMenu
{
    NSLog(@"Cancelled");
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller
{
    NSLog(@"Cancelled");
}

- (void)documentMenu:(UIDocumentMenuViewController *)documentMenu didPickDocumentPicker:(UIDocumentPickerViewController *)documentPicker
{
    documentPicker.delegate = self;
    [self presentViewController:documentPicker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url
{
    if (controller.documentPickerMode == UIDocumentPickerModeImport) {
        
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        __block NSError *error;
        
        [coordinator coordinateReadingItemAtURL:url options:NSFileCoordinatorReadingForUploading error:&error byAccessor:^(NSURL *newURL) {
            
            NSString *fileName = [url lastPathComponent];
            NSString *fileNamePath = [NSString stringWithFormat:@"%@/%@", app.directoryUser, fileName];
            NSData *data = [NSData dataWithContentsOfURL:newURL];
            
            if (data && error == nil) {
                
                if ([data writeToFile:fileNamePath options:NSDataWritingAtomic error:&error]) {
                    
                    // Upload File
                    [[CCNetworking sharedNetworking] uploadFile:fileName serverUrl:_serverUrl cryptated:_isPickerCriptate onlyPlist:NO session:k_upload_session taskStatus: k_taskStatusResume selector:nil selectorPost:nil errorCode:0 delegate:nil];
                    
                } else {
                    
                    [app messageNotification:@"_error_" description:error.description visible:YES delay:k_dismissAfterSecond type:TWMessageBarMessageTypeError errorCode:error.code];
                }
                
            } else {
                
                [app messageNotification:@"_error_" description:@"_read_file_error_" visible:YES delay:k_dismissAfterSecond type:TWMessageBarMessageTypeError errorCode:error.code];
            }
        }];
    }
}

- (void)openImportDocumentPicker
{
    UIDocumentMenuViewController *documentProviderMenu = [[UIDocumentMenuViewController alloc] initWithDocumentTypes:@[@"public.data"] inMode:UIDocumentPickerModeImport];
    
    documentProviderMenu.modalPresentationStyle = UIModalPresentationFormSheet;
    documentProviderMenu.popoverPresentationController.sourceView = self.view;
    documentProviderMenu.popoverPresentationController.sourceRect = self.view.bounds;
    documentProviderMenu.delegate = self;
    
    [self presentViewController:documentProviderMenu animated:YES completion:nil];
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Assets Picker =====
#pragma --------------------------------------------------------------------------------------------

- (void)openAssetsPickerController
{
    CTAssetCheckmark *checkmark = [CTAssetCheckmark appearance];
    checkmark.tintColor = [NCBrandColor sharedInstance].brand;
    [checkmark setMargin:0.0 forVerticalEdge:NSLayoutAttributeRight horizontalEdge:NSLayoutAttributeTop];
    
    UINavigationBar *navBar = [UINavigationBar appearanceWhenContainedIn:[CTAssetsPickerController class], nil];
    [app aspectNavigationControllerBar:navBar encrypted:NO online:YES hidden:NO];
    
    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status){
        dispatch_async(dispatch_get_main_queue(), ^{
            
            // init picker
            CTAssetsPickerController *picker = [[CTAssetsPickerController alloc] init];
            
            // set delegate
            picker.delegate = self;
            
            // to show selection order
            //picker.showsSelectionIndex = YES;
            
            // to present picker as a form sheet in iPad
            if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
                picker.modalPresentationStyle = UIModalPresentationFormSheet;
            
            // present picker
            [self presentViewController:picker animated:YES completion:nil];
        });
    }];
}

- (void)assetsPickerController:(CTAssetsPickerController *)picker didFinishPickingAssets:(NSMutableArray *)assets
{
    [picker dismissViewControllerAnimated:YES completion:^{
        
        CreateFormUploadAssets *form = [[CreateFormUploadAssets alloc] init:_titleMain serverUrl:_serverUrl assets:assets cryptated:_isPickerCriptate session:k_upload_session];
        form.title = NSLocalizedString(@"_upload_photos_videos_", nil);
        
        UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:form];
        
        [navigationController setModalPresentationStyle:UIModalPresentationFormSheet];
        
        //navController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
        
        [self presentViewController:navigationController animated:YES completion:nil];        
    }];
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== UIDocumentInteractionControllerDelegate =====
#pragma --------------------------------------------------------------------------------------------

- (void)documentInteractionControllerDidDismissOptionsMenu:(UIDocumentInteractionController *)controller
{
    // evitiamo il rimando della eventuale photo e/o video
    tableAccount *tableAccount = [[NCManageDatabase sharedInstance] getAccountActive];
    if (tableAccount.cameraUpload) {
        
        [CCCoreData setCameraUploadDatePhoto:[NSDate date]];
        [CCCoreData setCameraUploadDateVideo:[NSDate date]];
        
    }
    
    /*
    if ([CCCoreData getCameraUploadActiveAccount:app.activeAccount]) {
        
        [CCCoreData setCameraUploadDatePhoto:[NSDate date]];
        [CCCoreData setCameraUploadDateVideo:[NSDate date]];
    }
    */
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== UnZipFile =====
#pragma --------------------------------------------------------------------------------------------

- (void)unZipFile:(NSString *)fileID
{
    [_hudDeterminate visibleHudTitle:NSLocalizedString(@"_unzip_in_progress_", nil) mode:MBProgressHUDModeDeterminate color:nil];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        NSString *fileZip = [NSString stringWithFormat:@"%@/%@", app.directoryUser, fileID];
        
        [SSZipArchive unzipFileAtPath:fileZip toDestination:[CCUtility getDirectoryLocal] overwrite:YES password:nil progressHandler:^(NSString *entry, unz_file_info zipInfo, long entryNumber, long total) {
                          
            dispatch_async(dispatch_get_main_queue(), ^{
                float progress = (float) entryNumber / (float)total;
                [_hudDeterminate progress:progress];
            });
                          
        } completionHandler:^(NSString *path, BOOL succeeded, NSError *error) {
                        
            dispatch_async(dispatch_get_main_queue(), ^{
                
                [_hudDeterminate hideHud];
                
                if (succeeded) [app messageNotification:@"_info_" description:@"_file_unpacked_" visible:YES delay:k_dismissAfterSecond type:TWMessageBarMessageTypeSuccess  errorCode:0];
                else [app messageNotification:@"_error_" description:[NSString stringWithFormat:@"Error %ld", (long)error.code] visible:YES delay:k_dismissAfterSecond type:TWMessageBarMessageTypeError errorCode:0];
            });
                        
        }];
    });
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Create New (OpenModel) =====
#pragma --------------------------------------------------------------------------------------------

- (void)openModel:(NSString *)tipo isNew:(BOOL)isnew
{
    UIViewController *viewController;
    NSString *fileName, *uuid, *fileID, *serverUrl;
    
    NSIndexPath * index = [self.tableView indexPathForSelectedRow];
    [self.tableView deselectRowAtIndexPath:index animated:NO];
    
    if (isnew) {
        
        fileName = nil;
        uuid = [CCUtility getUUID];
        fileID = nil;
        serverUrl = _serverUrl;
        
    } else {
        
        fileName = _metadata.fileName;
        uuid = _metadata.uuid;
        fileID = _metadata.fileID;
        serverUrl = [CCCoreData getServerUrlFromDirectoryID:_metadata.directoryID activeAccount:_metadata.account];
    }
    
    if ([tipo isEqualToString:@"cartadicredito"])
        viewController = [[CCCartaDiCredito alloc] initWithDelegate:self fileName:fileName uuid:uuid fileID:fileID isLocal:NO serverUrl:serverUrl];
    
    if ([tipo isEqualToString:@"bancomat"])
        viewController = [[CCBancomat alloc] initWithDelegate:self fileName:fileName uuid:uuid fileID:fileID  isLocal:NO serverUrl:serverUrl];
    
    if ([tipo isEqualToString:@"contocorrente"])
        viewController = [[CCContoCorrente alloc] initWithDelegate:self fileName:fileName uuid:uuid fileID:fileID isLocal:NO serverUrl:serverUrl];
    
    if ([tipo isEqualToString:@"accountweb"])
        viewController = [[CCAccountWeb alloc] initWithDelegate:self fileName:fileName uuid:uuid fileID:fileID isLocal:NO serverUrl:serverUrl];
    
    if ([tipo isEqualToString:@"patenteguida"])
        viewController = [[CCPatenteGuida alloc] initWithDelegate:self fileName:fileName uuid:uuid fileID:fileID isLocal:NO serverUrl:serverUrl];
    
    if ([tipo isEqualToString:@"cartaidentita"])
        viewController = [[CCCartaIdentita alloc] initWithDelegate:self fileName:fileName uuid:uuid fileID:fileID isLocal:NO serverUrl:serverUrl];
    
    if ([tipo isEqualToString:@"passaporto"])
        viewController = [[CCPassaporto alloc] initWithDelegate:self fileName:fileName uuid:uuid fileID:fileID isLocal:NO serverUrl:serverUrl];
    
    if ([tipo isEqualToString:@"note"]) {
        
        viewController = [[CCNote alloc] initWithDelegate:self fileName:fileName uuid:uuid fileID:fileID isLocal:NO serverUrl:serverUrl];
        
        UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:viewController];
        
        [self presentViewController:navigationController animated:YES completion:nil];
        
    } else {
    
        UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:viewController];
        
        [navigationController setModalPresentationStyle:UIModalPresentationFormSheet];
        
        [self presentViewController:navigationController animated:YES completion:nil];
    }
}

// New folder or new photo or video
- (void)returnCreate:(NSInteger)type
{
    switch (type) {
            
        /* PLAIN */
        case k_returnCreateFolderPlain: {
            UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"_create_folder_",nil) message:nil delegate:self cancelButtonTitle:NSLocalizedString(@"_cancel_",nil) otherButtonTitles:NSLocalizedString(@"_save_", nil), nil];
            [alertView setAlertViewStyle:UIAlertViewStylePlainTextInput];
            alertView.tag = alertCreateFolder;
            [alertView show];
        }
            break;
        case k_returnCreateFotoVideoPlain: {
            
            _isPickerCriptate = false;
            
            [self openAssetsPickerController];
        }
            break;
        case k_returnCreateFilePlain: {
            
            _isPickerCriptate = false;
            
            [self openImportDocumentPicker];
        }
            break;
            
            
        /* ENCRYPTED */
        case k_returnCreateFolderEncrypted: {
            
            UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"_create_folder_",nil) message:nil delegate:self cancelButtonTitle:NSLocalizedString(@"_cancel_",nil) otherButtonTitles:NSLocalizedString(@"_save_", nil), nil];
            [alertView setAlertViewStyle:UIAlertViewStylePlainTextInput];
            alertView.tag = alertCreateFolderCrypto;
            [alertView show];
        }
            break;
        case k_returnCreateFotoVideoEncrypted: {
            
            _isPickerCriptate = true;
            
            [self openAssetsPickerController];
        }
            break;
        case k_returnCreateFileEncrypted: {
            
            _isPickerCriptate = true;
            
            [self openImportDocumentPicker];
        }
            break;
    
        /* UTILITY */
        case k_returnNote:
            [self openModel:@"note" isNew:true];
            break;
        case k_returnAccountWeb:
            [self openModel:@"accountweb" isNew:true];
            break;
            
         /* BANK */
        case k_returnCartaDiCredito:
            [self openModel:@"cartadicredito" isNew:true];
            break;
        case k_returnBancomat:
            [self openModel:@"bancomat" isNew:true];
            break;
        case k_returnContoCorrente:
            [self openModel:@"contocorrente" isNew:true];
            break;
       
        /* DOCUMENT */
        case k_returnPatenteGuida:
            [self openModel:@"patenteguida" isNew:true];
            break;
        case k_returnCartaIdentita:
            [self openModel:@"cartaidentita" isNew:true];
            break;
        case k_returnPassaporto:
            [self openModel:@"passaporto" isNew:true];
            break;
    }
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Save selected File =====
#pragma --------------------------------------------------------------------------------------------

-(void)saveSelectedFilesSelector:(NSString *)path didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo
{
    if (error)
        [app messageNotification:@"_save_selected_files_" description:@"_file_not_saved_cameraroll_" visible:YES delay:k_dismissAfterSecond type:TWMessageBarMessageTypeError errorCode:error.code];
    else
        [app messageNotification:@"_save_selected_files_" description:@"_file_saved_cameraroll_" visible:YES delay:k_dismissAfterSecond type:TWMessageBarMessageTypeSuccess errorCode:error.code];
}

- (void)saveSelectedFiles
{
    NSLog(@"[LOG] Start download selected files ...");
    
    [_hud visibleHudTitle:@"" mode:MBProgressHUDModeIndeterminate color:nil];
    
    NSArray *metadatas = [self getMetadatasFromSelectedRows:[self.tableView indexPathsForSelectedRows]];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.01 * NSEC_PER_SEC), dispatch_get_main_queue(), ^(void) {
        
        for (CCMetadata *metadata in metadatas) {
            
            if (metadata.directory == NO && [metadata.type isEqualToString: k_metadataType_file] && ([metadata.typeFile isEqualToString: k_metadataTypeFile_image] || [metadata.typeFile isEqualToString: k_metadataTypeFile_video])) {
                
                NSString *serverUrl = [CCCoreData getServerUrlFromDirectoryID:metadata.directoryID activeAccount:metadata.account];
                
                [[CCNetworking sharedNetworking] downloadFile:metadata serverUrl:serverUrl downloadData:YES downloadPlist:NO selector:selectorSave selectorPost:nil session:k_download_session taskStatus: k_taskStatusResume delegate:self];
            }
        }
        
        [_hud hideHud];
    });
    
    [self tableViewSelect:NO];
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Change Password =====
#pragma --------------------------------------------------------------------------------------------

- (void) loginSuccess:(NSInteger)loginType
{
    [self readFolderWithForced:YES serverUrl:_serverUrl];
}

- (void)changePasswordAccount
{
    // Brand
    if ([NCBrandOptions sharedInstance].use_login_web) {
    
        _loginWeb = [CCLoginWeb new];
        _loginWeb.delegate = self;
        _loginWeb.loginType = loginModifyPasswordUser;
    
        dispatch_async(dispatch_get_main_queue(), ^ {
            [_loginWeb presentModalWithDefaultTheme:self];
        });
        
    } else {
        
        _loginVC = [[UIStoryboard storyboardWithName:@"CCLogin" bundle:nil] instantiateViewControllerWithIdentifier:@"CCLoginNextcloud"];
        _loginVC.delegate = self;
        _loginVC.loginType = loginModifyPasswordUser;
    
        [self presentViewController:_loginVC animated:YES completion:nil];
    }
}

#pragma mark -
#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Peek & Pop  =====
#pragma --------------------------------------------------------------------------------------------

- (UIViewController *)previewingContext:(id<UIViewControllerPreviewing>)previewingContext viewControllerForLocation:(CGPoint)location
{
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:location];
    CCMetadata *metadata = [self getMetadataFromSectionDataSource:indexPath];
    
    if (metadata.thumbnailExists && !metadata.cryptated) {
        CCCellMain *cell = [self.tableView cellForRowAtIndexPath:indexPath];
        
        if (cell) {
            previewingContext.sourceRect = cell.frame;
            CCPeekPop *vc = [[UIStoryboard storyboardWithName:@"CCPeekPop" bundle:nil] instantiateViewControllerWithIdentifier:@"PeekPopImagePreview"];
            
            vc.delegate = self;
            vc.metadata = metadata;
            
            return vc;
        }
    }
    
    return nil;
}

- (void)previewingContext:(id<UIViewControllerPreviewing>)previewingContext commitViewController:(UIViewController *)viewControllerToCommit
{
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:previewingContext.sourceRect.origin];
    
    [self tableView:self.tableView didSelectRowAtIndexPath:indexPath];
}

#pragma mark -

#pragma --------------------------------------------------------------------------------------------
#pragma mark ==== External Sites ====
#pragma --------------------------------------------------------------------------------------------

- (void)getExternalSitesServerSuccess:(NSArray *)listOfExternalSites
{
    [[NCManageDatabase sharedInstance] deleteExternalSitesForAccount:app.activeAccount];
    
    for (OCExternalSites *tableExternalSites in listOfExternalSites)
        [[NCManageDatabase sharedInstance] addExternalSites:tableExternalSites account:app.activeAccount];
}

- (void)getExternalSitesServerFailure:(CCMetadataNet *)metadataNet message:(NSString *)message errorCode:(NSInteger)errorCode
{
    NSLog(@"[LOG] No External Sites found");
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ==== Activity ====
#pragma --------------------------------------------------------------------------------------------

- (void)getActivityServerSuccess:(NSArray *)listOfActivity
{
    [[NCManageDatabase sharedInstance] addActivityServer:listOfActivity account:app.activeAccount];
    
    // Reload Activity Data Source
    [app.activeActivity reloadDatasource];
}

- (void)getActivityServerFailure:(CCMetadataNet *)metadataNet message:(NSString *)message errorCode:(NSInteger)errorCode
{
    NSLog(@"[LOG] No Activity found");
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ==== Notification  ====
#pragma --------------------------------------------------------------------------------------------

- (void)getNotificationServerSuccess:(NSArray *)listOfNotifications
{
    AppDelegate *appDelegate = (AppDelegate *)[[UIApplication sharedApplication] delegate];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        
        // Order by date
        NSArray *sortedListOfNotifications = [listOfNotifications sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
            
            OCNotifications *notification1 = obj1, *notification2 = obj2;
        
            return [notification2.date compare: notification1.date];
        
        }];
    
        // verify if listOfNotifications is changed
        NSString *old = @"", *new = @"";
        for (OCNotifications *notification in listOfNotifications)
            new = [new stringByAppendingString:@(notification.idNotification).stringValue];
        for (OCNotifications *notification in appDelegate.listOfNotifications)
            old = [old stringByAppendingString:@(notification.idNotification).stringValue];

        if (![new isEqualToString:old]) {
        
            appDelegate.listOfNotifications = [[NSMutableArray alloc] initWithArray:sortedListOfNotifications];
        
            // reload Notification view
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:@"notificationReloadData" object:nil];
            });
        }
    
        // Update NavigationBar
        if (!_isSelectedMode) {
            
            [self performSelectorOnMainThread:@selector(setUINavigationBarDefault) withObject:nil waitUntilDone:NO];
        }
    });
}

- (void)getNotificationServerFailure:(CCMetadataNet *)metadataNet message:(NSString *)message errorCode:(NSInteger)errorCode
{    
    // Update NavigationBar
    if (!_isSelectedMode)
        [self setUINavigationBarDefault];
}

- (void)viewNotification
{
    if ([app.listOfNotifications count] > 0) {
        
        CCNotification *notificationVC = [[UIStoryboard storyboardWithName:@"CCNotification" bundle:nil] instantiateViewControllerWithIdentifier:@"CCNotification"];
        
        [notificationVC setModalPresentationStyle:UIModalPresentationFormSheet];

        [self presentViewController:notificationVC animated:YES completion:nil];
    }
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ==== User Profile  ====
#pragma --------------------------------------------------------------------------------------------

- (void)getUserProfileFailure:(CCMetadataNet *)metadataNet message:(NSString *)message errorCode:(NSInteger)errorCode
{
    if (errorCode == 401)
        [self changePasswordAccount];
}

- (void)getUserProfileSuccess:(CCMetadataNet *)metadataNet userProfile:(OCUserProfile *)userProfile
{
    //[CCCoreData setUserProfileActiveAccount:metadataNet.account userProfile:userProfile];
    [[NCManageDatabase sharedInstance] setAccountsUserProfile:metadataNet.account userProfile:userProfile];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        
        NSString *address = [NSString stringWithFormat:@"%@/index.php/avatar/%@/128", app.activeUrl, app.activeUser];
        UIImage *avatar = [UIImage imageWithData:[NSData dataWithContentsOfURL:[NSURL URLWithString:[address stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]]]];
        if (avatar)
            [UIImagePNGRepresentation(avatar) writeToFile:[NSString stringWithFormat:@"%@/avatar.png", app.directoryUser] atomically:YES];
        else
            [[NSFileManager defaultManager] removeItemAtPath:[NSString stringWithFormat:@"%@/avatar.png", app.directoryUser] error:nil];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:@"changeUserProfile" object:nil];
        });
    });
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ==== Capabilities  ====
#pragma --------------------------------------------------------------------------------------------

- (void)getCapabilitiesOfServerFailure:(CCMetadataNet *)metadataNet message:(NSString *)message errorCode:(NSInteger)errorCode
{
    // Change Theming color
    [app settingThemingColorBrand];
    
    if (errorCode == 401)
        [self changePasswordAccount];
}

- (void)getCapabilitiesOfServerSuccess:(OCCapabilities *)capabilities
{
    // Update capabilities db
    [[NCManageDatabase sharedInstance] addCapabilities:capabilities account:app.activeAccount];
    
    // ------ THEMING -----------------------------------------------------------------------
    
    // Download Theming Background & Change Theming color
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        
        if ([NCBrandOptions sharedInstance].use_themingBackground == YES) {
        
            UIImage *themingBackground = [UIImage imageWithData:[NSData dataWithContentsOfURL:[NSURL URLWithString:[capabilities.themingBackground stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]]]];
            if (themingBackground)
                [UIImagePNGRepresentation(themingBackground) writeToFile:[NSString stringWithFormat:@"%@/themingBackground.png", app.directoryUser] atomically:YES];
            else
                [[NSFileManager defaultManager] removeItemAtPath:[NSString stringWithFormat:@"%@/themingBackground.png", app.directoryUser] error:nil];
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [app settingThemingColorBrand];
        });
    });

    // ------ SEARCH  ------------------------------------------------------------------------
    
    // Search bar if change version
    if ([[NCManageDatabase sharedInstance] getServerVersionAccount:app.activeAccount] != capabilities.versionMajor) {
    
        [self cancelSearchBar];
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.01 * NSEC_PER_SEC), dispatch_get_main_queue(), ^(void) {

            if (capabilities.versionMajor >= 12) {
                if (_isRoot)
                    self.searchController.searchBar.placeholder = NSLocalizedString(@"_search_all_folders_",nil);
                else
                    self.searchController.searchBar.placeholder = NSLocalizedString(@"_search_sub_folder_",nil);
                
                self.searchController.searchBar.scopeButtonTitles = [NSArray arrayWithObjects:NSLocalizedString(@"_search_this_folder_",nil),self.searchController.searchBar.placeholder, nil];
                
            } else {
                self.searchController.searchBar.placeholder = NSLocalizedString(@"_search_this_folder_",nil);
                self.searchController.searchBar.scopeButtonTitles = nil;
            }
            _depth = @"0";
        });
    }
    
    // ------ GET SERVICE SERVER ------------------------------------------------------------
    
    CCMetadataNet *metadataNet = [[CCMetadataNet alloc] initWithAccount:app.activeAccount];

    // Read External Sites
    if (capabilities.isExternalSitesServerEnabled) {
        
        metadataNet.action = actionGetExternalSitesServer;
        [app addNetworkingOperationQueue:app.netQueue delegate:self metadataNet:metadataNet];
    }
    
    // Read Share
    if (capabilities.isFilesSharingAPIEnabled) {
        
        [app.sharesID removeAllObjects];
        metadataNet.action = actionReadShareServer;
        [app addNetworkingOperationQueue:app.netQueue delegate:self metadataNet:metadataNet];
    }
    
    // Read Notification
    metadataNet.action = actionGetNotificationServer;
    [app addNetworkingOperationQueue:app.netQueue delegate:self metadataNet:metadataNet];
    
    // Read User Profile
    metadataNet.action = actionGetUserProfile;
    [app addNetworkingOperationQueue:app.netQueue delegate:self metadataNet:metadataNet];
    
    // Read Activity
    metadataNet.action = actionGetActivityServer;
    [app addNetworkingOperationQueue:app.netQueue delegate:self metadataNet:metadataNet];
}

#pragma mark -
#pragma --------------------------------------------------------------------------------------------
#pragma mark ==== Request Server Information  ====
#pragma --------------------------------------------------------------------------------------------

- (void)requestServerCapabilities
{
    // test
    if (app.activeAccount.length == 0)
        return;
    
    CCMetadataNet *metadataNet = [[CCMetadataNet alloc] initWithAccount:app.activeAccount];
    
    metadataNet.action = actionGetCapabilities;
    [app addNetworkingOperationQueue:app.netQueue delegate:self metadataNet:metadataNet];
}

#pragma mark -
#pragma --------------------------------------------------------------------------------------------
#pragma mark ==== Download Thumbnail Delegate ====
#pragma --------------------------------------------------------------------------------------------

- (void)downloadThumbnailSuccess:(CCMetadataNet *)metadataNet
{
    __block CCCellMain *cell;
    
    NSIndexPath *indexPath = [_sectionDataSource.fileIDIndexPath objectForKey:metadataNet.fileID];
    
    if (indexPath && [[NSFileManager defaultManager] fileExistsAtPath:[NSString stringWithFormat:@"%@/%@.ico", app.directoryUser, metadataNet.fileID]]) {
        
        cell = [self.tableView cellForRowAtIndexPath:indexPath];
        
        cell.fileImageView.image = [app.icoImagesCache objectForKey:metadataNet.fileID];
        
        if (cell.fileImageView.image == nil) {
            
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                
                UIImage *image = [UIImage imageWithContentsOfFile:[NSString stringWithFormat:@"%@/%@.ico", app.directoryUser, metadataNet.fileID]];
                
                [app.icoImagesCache setObject:image forKey:metadataNet.fileID];
            });
        }
     }
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ==== Download ====
#pragma --------------------------------------------------------------------------------------------

- (void)downloadFileFailure:(NSString *)fileID serverUrl:(NSString *)serverUrl selector:(NSString *)selector message:(NSString *)message errorCode:(NSInteger)errorCode
{
    CCMetadata *metadata = [CCCoreData getMetadataWithPreficate:[NSPredicate predicateWithFormat:@"(fileID == %@) AND (account == %@)", fileID, app.activeAccount] context:nil];
    
    // File do not exists on server, remove in local
    if (errorCode == kOCErrorServerPathNotFound || errorCode == kCFURLErrorBadServerResponse) {
        [CCCoreData deleteFile:metadata serverUrl:serverUrl directoryUser:app.directoryUser activeAccount:app.activeAccount];
    }
    
    if ([selector isEqualToString:selectorLoadViewImage]) {
        
        dispatch_async(dispatch_get_main_queue(), ^{

            // Updating Detail
            if (app.activeDetail)
                [app.activeDetail downloadPhotoBrowserFailure:errorCode];
            
            // Updating Photos
            if (app.activePhotosCameraUpload)
                [app.activePhotosCameraUpload downloadFileFailure:errorCode];
        });
        
    } else {
        
        if (errorCode != kCFURLErrorCancelled)
            [app messageNotification:@"_download_file_" description:message visible:YES delay:k_dismissAfterSecond type:TWMessageBarMessageTypeError errorCode:errorCode];
    }

    [self reloadDatasource:serverUrl fileID:metadata.fileID selector:selector];
}

- (void)downloadFileSuccess:(NSString *)fileID serverUrl:(NSString *)serverUrl selector:(NSString *)selector selectorPost:(NSString *)selectorPost
{
    CCMetadata *metadata = [CCCoreData getMetadataWithPreficate:[NSPredicate predicateWithFormat:@"(fileID == %@) AND (account == %@)", fileID, app.activeAccount] context:nil];
    
    if (metadata == nil) return;
    
    // Download
    if ([selector isEqualToString:selectorDownloadFile]) {
        [self reloadDatasource:serverUrl fileID:metadata.fileID selector:selector];
    }
    
    // Synchronized
    if ([selector isEqualToString:selectorDownloadSynchronize]) {
        
        [self reloadDatasource:serverUrl fileID:metadata.fileID selector:selector];
    }
    
    // add Favorite
    if ([selector isEqualToString:selectorAddFavorite]) {
        
        [[CCActions sharedInstance] settingFavorite:metadata favorite:YES delegate:self];
    }
    
    // add Offline
    if ([selector isEqualToString:selectorAddOffline]) {
        [CCCoreData setOfflineLocalFileID:metadata.fileID offline:YES activeAccount:app.activeAccount];
        [self reloadDatasource:serverUrl fileID:metadata.fileID selector:selector];
    }
    
    // encrypted file
    if ([selector isEqualToString:selectorEncryptFile]) {
        [self encryptedFile:metadata];
    }
    
    // decrypted file
    if ([selector isEqualToString:selectorDecryptFile]) {
        [self decryptedFile:metadata];
    }
    
    // open View File
    if ([selector isEqualToString:selectorLoadFileView] && [[UIApplication sharedApplication] applicationState] == UIApplicationStateActive) {
        
        [self reloadDatasource:serverUrl fileID:metadata.fileID selector:selector];
        
        if ([metadata.typeFile isEqualToString: k_metadataTypeFile_compress]) {
            
            [self performSelector:@selector(unZipFile:) withObject:metadata.fileID];
            
        } else if ([metadata.typeFile isEqualToString: k_metadataTypeFile_unknown]) {
            
            selector = selectorOpenIn;
           
        } else {
            
            _metadata = metadata;
    
            if ([self shouldPerformSegue])
                [self performSegueWithIdentifier:@"segueDetail" sender:self];
        }
    }
    
    // addLocal
    if ([selector isEqualToString:selectorAddLocal]) {
        
        [CCUtility copyFileAtPath:[NSString stringWithFormat:@"%@/%@", app.directoryUser, metadata.fileID] toPath:[NSString stringWithFormat:@"%@/%@", [CCUtility getDirectoryLocal], metadata.fileNamePrint]];
        
        UIImage *image = [UIImage imageWithContentsOfFile:[NSString stringWithFormat:@"%@/%@.ico", app.directoryUser, metadata.fileID]];
        [CCGraphics saveIcoWithFileID:metadata.fileNamePrint image:image writeToFile:nil copy:YES move:NO fromPath:[NSString stringWithFormat:@"%@/%@.ico", app.directoryUser, metadata.fileID] toPath:[NSString stringWithFormat:@"%@/.%@.ico", [CCUtility getDirectoryLocal], metadata.fileNamePrint]];
        
        [app messageNotification:@"_add_local_" description:@"_file_saved_local_" visible:YES delay:k_dismissAfterSecond type:TWMessageBarMessageTypeSuccess errorCode:0];
        
        [self reloadDatasource:serverUrl fileID:metadata.fileID selector:selector];
    }
    
    // Open with...
    if ([selector isEqualToString:selectorOpenIn] && [[UIApplication sharedApplication] applicationState] == UIApplicationStateActive) {
        
        [self reloadDatasource:serverUrl fileID:metadata.fileID selector:selector];
        
        [[NSFileManager defaultManager] removeItemAtPath:[NSTemporaryDirectory() stringByAppendingString:metadata.fileNamePrint] error:nil];
        [[NSFileManager defaultManager] linkItemAtPath:[NSString stringWithFormat:@"%@/%@", app.directoryUser, metadata.fileID] toPath:[NSTemporaryDirectory() stringByAppendingString:metadata.fileNamePrint] error:nil];
        NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingString:metadata.fileNamePrint]];
        
        _docController = [UIDocumentInteractionController interactionControllerWithURL:url];
        _docController.delegate = self;
        
        [_docController presentOptionsMenuFromRect:self.view.frame inView:self.view animated:YES];
    }
    
    // Save to Photo Album
    if ([selector isEqualToString:selectorSave] && [[UIApplication sharedApplication] applicationState] == UIApplicationStateActive) {
        
        NSString *file = [NSString stringWithFormat:@"%@/%@", app.directoryUser, metadata.fileID];
        
        if ([metadata.typeFile isEqualToString: k_metadataTypeFile_image]) {
            
            // evitiamo il rimando photo
            [CCCoreData setCameraUploadDatePhoto:[NSDate date]];

            UIImage *image = [UIImage imageWithContentsOfFile:file];
            
            if (image)
                UIImageWriteToSavedPhotosAlbum(image, self, @selector(saveSelectedFilesSelector: didFinishSavingWithError: contextInfo:), nil);
            else
                [app messageNotification:@"_save_selected_files_" description:@"_file_not_saved_cameraroll_" visible:YES delay:k_dismissAfterSecond type:TWMessageBarMessageTypeError errorCode:0];
        }
        
        if ([metadata.typeFile isEqualToString: k_metadataTypeFile_video]) {
            
            // we avoid the cross-reference video
            [CCCoreData setCameraUploadDateVideo:[NSDate date]];
            
            [[NSFileManager defaultManager] linkItemAtPath:file toPath:[NSTemporaryDirectory() stringByAppendingString:metadata.fileNamePrint] error:nil];
            
            if (UIVideoAtPathIsCompatibleWithSavedPhotosAlbum([NSTemporaryDirectory() stringByAppendingString:metadata.fileNamePrint])) {
                
                UISaveVideoAtPathToSavedPhotosAlbum([NSTemporaryDirectory() stringByAppendingString:metadata.fileNamePrint], self, @selector(saveSelectedFilesSelector: didFinishSavingWithError: contextInfo:), nil);
            } else {
                [app messageNotification:@"_save_selected_files_" description:@"_file_not_saved_cameraroll_" visible:YES delay:k_dismissAfterSecond type:TWMessageBarMessageTypeError errorCode:0];
            }
        }
        
        [self reloadDatasource:serverUrl fileID:metadata.fileID selector:selector];
    }
    
    // Copy File
    if ([selector isEqualToString:selectorLoadCopy]) {
        
        [self reloadDatasource:serverUrl fileID:metadata.fileID selector:selector];
        
        [self copyFileToPasteboard:metadata];
    }
    
    // download and view a template
    if ([selector isEqualToString:selectorLoadModelView]) {
        
        [CCCoreData downloadFilePlist:metadata activeAccount:app.activeAccount activeUrl:app.activeUrl directoryUser:app.directoryUser];
        
        [self openModel:metadata.model isNew:false];
        
        [self reloadDatasource:serverUrl fileID:metadata.fileID selector:selector];
    }
    
    //download file plist
    if ([selector isEqualToString:selectorLoadPlist]) {
        
        [CCCoreData downloadFilePlist:metadata activeAccount:app.activeAccount activeUrl:app.activeUrl directoryUser:app.directoryUser];
        
        long countSelectorLoadPlist = 0;
        
        for (NSOperation *operation in [app.netQueue operations]) {
            
            if ([((OCnetworking *)operation).metadataNet.selector isEqualToString:selectorLoadPlist])
                countSelectorLoadPlist++;
        }
        
        if ((countSelectorLoadPlist == 0 || countSelectorLoadPlist % k_maxConcurrentOperation == 0) && [metadata.directoryID isEqualToString:[CCCoreData getDirectoryIDFromServerUrl:_serverUrl activeAccount:app.activeAccount]]) {
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [self reloadDatasource:serverUrl fileID:metadata.fileID selector:selector];
            });
        }
    }
    
    //selectorLoadViewImage
    if ([selector isEqualToString:selectorLoadViewImage]) {
        
        dispatch_async(dispatch_get_main_queue(), ^{
            
            // Detail
            if (app.activeDetail)
                [app.activeDetail downloadPhotoBrowserSuccess:metadata selector:selector];
            
            // Photos
            if (app.activePhotosCameraUpload)
                [app.activePhotosCameraUpload downloadFileSuccess:metadata];
        });

        [self reloadDatasource:serverUrl fileID:metadata.fileID selector:selector];
    }
    
    // if exists postselector call self with selectorPost
    if ([selectorPost length] > 0)
        [self downloadFileSuccess:fileID serverUrl:serverUrl selector:selectorPost selectorPost:nil];
}

- (void)downloadSelectedFiles
{
    NSLog(@"[LOG] Start download selected files ...");
    
    [_hud visibleHudTitle:NSLocalizedString(@"_downloading_progress_", nil) mode:MBProgressHUDModeIndeterminate color:nil];
    
    NSArray *selectedMetadatas = [self getMetadatasFromSelectedRows:[self.tableView indexPathsForSelectedRows]];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^(void) {
        
        for (CCMetadata *metadata in selectedMetadatas) {
            
            if (metadata.directory == NO && [metadata.type isEqualToString: k_metadataType_file]) {
                
                NSString *serverUrl = [CCCoreData getServerUrlFromDirectoryID:metadata.directoryID activeAccount:metadata.account];
                
                [[CCNetworking sharedNetworking] downloadFile:metadata serverUrl:serverUrl downloadData:YES downloadPlist:NO selector:selectorDownloadFile selectorPost:nil session:k_download_session taskStatus: k_taskStatusResume delegate:self];
            }
        }
        
        [_hud hideHud];
    });
    
    [self tableViewSelect:NO];
}

- (void)downloadPlist:(NSString *)directoryID serverUrl:(NSString *)serverUrl
{
    NSArray *records = [CCCoreData getTableMetadataWithPredicate:[NSPredicate predicateWithFormat:@"(account == %@) AND (directoryID == %@) AND ((session == NULL) OR (session == ''))", app.activeAccount, directoryID] context:nil];
    
    for (TableMetadata *recordMetadata in records) {
            
        if ([CCUtility isCryptoPlistString:recordMetadata.fileName] && [[NSFileManager defaultManager] fileExistsAtPath:[NSString stringWithFormat:@"%@/%@", app.directoryUser, recordMetadata.fileName]] == NO && [recordMetadata.session length] == 0) {
        
            CCMetadataNet *metadataNet = [[CCMetadataNet alloc] initWithAccount:app.activeAccount];
                
            metadataNet.action = actionDownloadFile;
            metadataNet.metadata = [CCCoreData insertEntityInMetadata:recordMetadata];
            metadataNet.downloadData = NO;
            metadataNet.downloadPlist = YES;
            metadataNet.selector = selectorLoadPlist;
            metadataNet.serverUrl = serverUrl;
            metadataNet.session = k_download_session_foreground;
            metadataNet.taskStatus = k_taskStatusResume;
            
            [app addNetworkingOperationQueue:app.netQueue delegate:self metadataNet:metadataNet];
        }
    }
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Upload new Photos/Videos =====
#pragma --------------------------------------------------------------------------------------------

- (void)uploadFileFailure:(CCMetadataNet *)metadataNet fileID:(NSString *)fileID serverUrl:(NSString *)serverUrl selector:(NSString *)selector message:(NSString *)message errorCode:(NSInteger)errorCode
{
    // Automatic upload All
    if([selector isEqualToString:selectorUploadAutomaticAll])
        [app performSelectorOnMainThread:@selector(loadAutomaticUpload) withObject:nil waitUntilDone:NO];
    
    // Read File test do not exists
    if (errorCode == k_CCErrorFileUploadNotFound && fileID) {
       
        CCMetadata *metadata = [CCCoreData getMetadataWithPreficate:[NSPredicate predicateWithFormat:@"(fileID == %@) AND (account == %@)", fileID, app.activeAccount] context:nil];
        
        // reUpload
        if (metadata)
            [[CCNetworking sharedNetworking] uploadFileMetadata:metadata taskStatus:k_taskStatusResume];
    }
    
    // Print error
    else if (errorCode != kCFURLErrorCancelled && errorCode != 403) {
        
        [app messageNotification:@"_upload_file_" description:message visible:YES delay:k_dismissAfterSecond type:TWMessageBarMessageTypeError errorCode:errorCode];
    }
    
    [self reloadDatasource:serverUrl fileID:nil selector:selector];
}

- (void)uploadFileSuccess:(CCMetadataNet *)metadataNet fileID:(NSString *)fileID serverUrl:(NSString *)serverUrl selector:(NSString *)selector selectorPost:(NSString *)selectorPost
{
    // Automatic upload All
    if([selector isEqualToString:selectorUploadAutomaticAll])
        [app performSelectorOnMainThread:@selector(loadAutomaticUpload) withObject:nil waitUntilDone:NO];
    
    if ([selectorPost isEqualToString:selectorReadFolderForced] ) {
            
        [self readFolderWithForced:YES serverUrl:serverUrl];
            
    } else {
    
        [self reloadDatasource:serverUrl fileID:nil selector:selector];
    }
}

//
// This procedure with performSelectorOnMainThread it's necessary after (Bridge) for use the function "Sync" in OCNetworking
//
- (void)uploadFileAsset:(NSMutableArray *)assets serverUrl:(NSString *)serverUrl cryptated:(BOOL)cryptated useSubFolder:(BOOL)useSubFolder session:(NSString *)session
{
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.01 * NSEC_PER_SEC), dispatch_get_main_queue(), ^(void){
        [self performSelectorOnMainThread:@selector(uploadFileAssetBridge:) withObject:@[assets, serverUrl, [NSNumber numberWithBool:cryptated], [NSNumber numberWithBool:useSubFolder], session] waitUntilDone:NO];
    });
}

- (void)uploadFileAssetBridge:(NSArray *)arguments
{
    NSArray *assets = [arguments objectAtIndex:0];
    NSString *serverUrl = [arguments objectAtIndex:1];
    BOOL cryptated = [[arguments objectAtIndex:2] boolValue];
    BOOL useSubFolder = [[arguments objectAtIndex:3] boolValue];
    NSString *session = [arguments objectAtIndex:4];
    
    //NSString *folderPhotos = [CCCoreData getCameraUploadFolderNamePathActiveAccount:app.activeAccount activeUrl:app.activeUrl];
    NSString *folderPhotos = [[NCManageDatabase sharedInstance] getAccountsCameraUploadFolderName:app.activeAccount activeUrl:app.activeUrl];

    NSString *directoryID = [CCCoreData getDirectoryIDFromServerUrl:serverUrl activeAccount:app.activeAccount];
    
    // Create the folder for Photos & if request the subfolders
    if (![app createFolderSubFolderAutomaticUploadFolderPhotos:folderPhotos useSubFolder:useSubFolder assets:assets selector:selectorUploadFile])
        return;
    
    NSLog(@"[LOG] Asset N. %lu", (unsigned long)[assets count]);
    
    for (PHAsset *asset in assets) {
        
        NSString *fileName = [CCUtility createFileNameFromAsset:asset key: k_keyFileNameMask];
        
        NSDate *assetDate = asset.creationDate;
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        
        // Create serverUrl if use sub folder
        if (useSubFolder) {
            
            [formatter setDateFormat:@"yyyy"];
            NSString *yearString = [formatter stringFromDate:assetDate];
        
            [formatter setDateFormat:@"MM"];
            NSString *monthString = [formatter stringFromDate:assetDate];
            
            serverUrl = [NSString stringWithFormat:@"%@/%@/%@", folderPhotos, yearString, monthString];
        }
        
        // Check if is in upload 
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"(account == %@) AND (directoryID == %@) AND (fileName == %@) AND (session != NULL) AND (session != '')", app.activeAccount, directoryID, fileName];
        NSArray *isRecordInSessions = [CCCoreData getTableMetadataWithPredicate:predicate context:nil];

        if ([isRecordInSessions count] > 0) {
            
            // next upload
            continue;
            
        } else {
            
            CCMetadataNet *metadataNet = [[CCMetadataNet alloc] initWithAccount:app.activeAccount];
            
            metadataNet.action = actionReadFile;
            metadataNet.assetLocalIdentifier = asset.localIdentifier;
            metadataNet.cryptated = cryptated;
            metadataNet.fileName = fileName;
            metadataNet.priority = NSOperationQueuePriorityNormal;
            metadataNet.session = session;
            metadataNet.selector = selectorReadFileUploadFile;
            metadataNet.serverUrl = serverUrl;
                
            [app addNetworkingOperationQueue:app.netQueue delegate:self metadataNet:metadataNet];
        }
    }
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ==== Read File ====
#pragma --------------------------------------------------------------------------------------------

- (void)readFileFailure:(CCMetadataNet *)metadataNet message:(NSString *)message errorCode:(NSInteger)errorCode
{
    // UploadFile
    if ([metadataNet.selector isEqualToString:selectorReadFileUploadFile]) {
        
        // File not exists
        if (errorCode == 404) {
            
            metadataNet.action = actionUploadAsset;
            metadataNet.errorCode = 0;
            metadataNet.selector = selectorUploadFile;
            metadataNet.selectorPost = nil;
            metadataNet.taskStatus = k_taskStatusResume;
            
            if ([metadataNet.session containsString:@"wwan"])
                [app addNetworkingOperationQueue:app.netQueueUploadWWan delegate:self metadataNet:metadataNet];
            else
                [app addNetworkingOperationQueue:app.netQueueUpload delegate:self metadataNet:metadataNet];
            
        } else {
            
            // error ho many retry befor notification and go to on next asses
            if (metadataNet.errorRetry < 3) {
                
                // Retry read file
                [app addNetworkingOperationQueue:app.netQueue delegate:self metadataNet:metadataNet];
                
            } else {
                
                // STOP check file, view message error
                [app messageNotification:@"_upload_file_" description:message visible:YES delay:k_dismissAfterSecond type:TWMessageBarMessageTypeError errorCode:errorCode];
            }
        }
    }
}

- (void)readFileSuccess:(CCMetadataNet *)metadataNet metadata:(CCMetadata *)metadata
{
    // UploadFile
    if ([metadataNet.selector isEqualToString:selectorReadFileUploadFile]) {
        
        metadataNet.action = actionUploadAsset;
        metadataNet.errorCode = 403;                // File exists 403 Forbidden
        metadataNet.selector = selectorUploadFile;
        metadataNet.selectorPost = nil;
        metadataNet.taskStatus = k_taskStatusResume;
        
        if ([metadataNet.session containsString:@"wwan"])
            [app addNetworkingOperationQueue:app.netQueueUploadWWan delegate:self metadataNet:metadataNet];
        else
            [app addNetworkingOperationQueue:app.netQueueUpload delegate:self metadataNet:metadataNet];
    }
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ==== Read Folder ====
#pragma --------------------------------------------------------------------------------------------

- (void)readFolderFailure:(CCMetadataNet *)metadataNet message:(NSString *)message errorCode:(NSInteger)errorCode
{
    // verify active user
    //TableAccount *record = [CCCoreData getActiveAccount];
    tableAccount *record = [[NCManageDatabase sharedInstance] getAccountActive];
    
    [_hud hideHud];

    [_refreshControl endRefreshing];
        
    [_ImageTitleHomeCryptoCloud setUserInteractionEnabled:YES];
    
    if (message && [record.account isEqualToString:metadataNet.account])
        [app messageNotification:@"_error_" description:message visible:YES delay:k_dismissAfterSecond type:TWMessageBarMessageTypeError errorCode:errorCode];
    
    [self reloadDatasource:metadataNet.serverUrl fileID:nil selector:metadataNet.selector];
    
    if (errorCode == 401)
        [self changePasswordAccount];
}

- (void)readFolderSuccess:(CCMetadataNet *)metadataNet permissions:(NSString *)permissions etag:(NSString *)etag metadatas:(NSArray *)metadatas
{
    // verify active user
    //TableAccount *record = [CCCoreData getActiveAccount];
    tableAccount *record = [[NCManageDatabase sharedInstance] getAccountActive];

    if (![record.account isEqualToString:metadataNet.account])
        return;
    
    // save father e update permission
    if(!_isSearchMode)
        _fatherPermission = permissions;
    
    NSArray *recordsInSessions;
    
    if (_isSearchMode) {
        
        recordsInSessions = [CCCoreData getTableMetadataWithPredicate:[NSPredicate predicateWithFormat:@"(account == %@) AND (session != NULL) AND (session != '')", metadataNet.account] context:nil];
        
    } else {
        
        [CCCoreData updateDirectoryEtagServerUrl:metadataNet.serverUrl etag:etag activeAccount:metadataNet.account];
        
        [CCCoreData deleteMetadataWithPredicate:[NSPredicate predicateWithFormat:@"(account == %@) AND (directoryID == %@) AND ((session == NULL) OR (session == ''))", metadataNet.account, metadataNet.directoryID]];
    
        recordsInSessions = [CCCoreData getTableMetadataWithPredicate:[NSPredicate predicateWithFormat:@"(account == %@) AND (directoryID == %@) AND (session != NULL) AND (session != '')", metadataNet.account, metadataNet.directoryID] context:nil];

        [CCCoreData setDateReadDirectoryID:metadataNet.directoryID activeAccount:app.activeAccount];
    }
    
    for (CCMetadata *metadata in metadatas) {
        
        // Delete Record only in Search Mode
        if (_isSearchMode)
            [CCCoreData deleteMetadataWithPredicate:[NSPredicate predicateWithFormat:@"(account == %@) AND (directoryID == %@) AND (fileID = %@) AND ((session == NULL) OR (session == ''))", metadataNet.account, metadata.directoryID, metadata.fileID]];
        
        // type of file
        NSInteger typeFilename = [CCUtility getTypeFileName:metadata.fileName];
        
        // if crypto do not insert
        if (typeFilename == k_metadataTypeFilenameCrypto) continue;
        
        // verify if the record encrypted has plist + crypto
        if (typeFilename == k_metadataTypeFilenamePlist && metadata.directory == NO) {
            
            BOOL isCryptoComplete = NO;
            NSString *fileNameCrypto = [CCUtility trasformedFileNamePlistInCrypto:metadata.fileName];
            
            for (CCMetadata *completeMetadata in metadatas) {
                    
                if (completeMetadata.cryptated == NO) continue;
                else  if ([completeMetadata.fileName isEqualToString:fileNameCrypto]) {
                    isCryptoComplete = YES;
                    break;
                }
            }
            if (isCryptoComplete == NO) continue;
        }
        
        // verify if the record is in download/upload progress
        if (metadata.directory == NO && [recordsInSessions count] > 0) {
            
            CCMetadata *metadataDB = [CCCoreData getMetadataWithPreficate:[NSPredicate predicateWithFormat:@"(account == %@) AND (directoryID == %@) AND (fileName == %@)", app.activeAccount, metadataNet.directoryID, metadata.fileName] context:nil];
            
            // is in Upload
            if (metadataDB.session && [metadataDB.session containsString:@"upload"]) {
                
                NSString *sessionID = metadataDB.sessionID;
                
                // rename SessionID -> fileID
                [CCUtility moveFileAtPath:[NSString stringWithFormat:@"%@/%@", app.directoryUser, sessionID]  toPath:[NSString stringWithFormat:@"%@/%@", app.directoryUser, metadata.fileID]];
                
                metadataDB.session = @"";
                metadataDB.date = metadata.date;
                metadataDB.fileID = metadata.fileID;
                metadataDB.rev = metadata.fileID;
                metadataDB.sessionError = @"";
                metadataDB.sessionID = @"";
                metadataDB.sessionTaskIdentifier = k_taskIdentifierDone;
                metadataDB.sessionTaskIdentifierPlist = k_taskIdentifierDone;
                
                [CCCoreData updateMetadata:metadataDB predicate:[NSPredicate predicateWithFormat:@"(sessionID == %@) AND (account == %@)", sessionID, app.activeAccount] activeAccount:app.activeAccount activeUrl:app.activeUrl context:nil];
                
                [CCCoreData addLocalFile:metadataDB activeAccount:app.activeAccount];
                
                [CCGraphics createNewImageFrom:metadata.fileID directoryUser:app.directoryUser fileNameTo:metadata.fileID fileNamePrint:metadata.fileNamePrint size:@"m" imageForUpload:NO typeFile:metadata.typeFile writePreview:YES optimizedFileName:[CCUtility getOptimizedPhoto]];
                
                continue;
            }
            
            // download in progress
            if (metadataDB.session && [metadataDB.session containsString:@"download"])
                continue;
        }

        // end test, insert in CoreData
        [CCCoreData addMetadata:metadata activeAccount:app.activeAccount activeUrl:app.activeUrl context:nil];
    }
    
    // read plist
    [self downloadPlist:metadataNet.directoryID serverUrl:metadataNet.serverUrl];
    
    // File is changed ??
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        if (!_isSearchMode)
            [[CCSynchronize sharedSynchronize] verifyChangeMedatas:metadatas serverUrl:metadataNet.serverUrl account:app.activeAccount withDownload:NO];
    });

    // Search Mode
    if (_isSearchMode)
        [self reloadDatasource:metadataNet.serverUrl fileID:nil selector:metadataNet.selector];
    
    // this is the same directory
    if ([metadataNet.serverUrl isEqualToString:_serverUrl] && !_isSearchMode) {
        
        // reload
        [self reloadDatasource:metadataNet.serverUrl fileID:nil selector:metadataNet.selector];
    
        // stoprefresh
        [_refreshControl endRefreshing];
    
        // Enable change user
        [_ImageTitleHomeCryptoCloud setUserInteractionEnabled:YES];
                
        [_hud hideHud];
    }
}

- (void)readFolderWithForced:(BOOL)forced serverUrl:(NSString *)serverUrl
{
    // init control
    if (!serverUrl || !app.activeAccount)
        return;
    
    // Search Mode
    if (_isSearchMode) {
        
        if (forced) {
            
            [CCCoreData clearDateReadAccount:app.activeAccount serverUrl:serverUrl directoryID:nil];
            
            _searchFileName = @"";                          // forced reload searchg
        }
        
        [self updateSearchResultsForSearchController:self.searchController];
        
        return;
    }
    
    NSString *directoryID = [CCCoreData getDirectoryIDFromServerUrl:serverUrl activeAccount:app.activeAccount];
    
    if ([CCCoreData isDirectoryOutOfDate:k_dayForceReadFolder directoryID:directoryID activeAccount:app.activeAccount] || forced) {
        
        if (_refreshControl.isRefreshing == NO)
            [_hud visibleIndeterminateHud];
        
        CCMetadataNet *metadataNet = [[CCMetadataNet alloc] initWithAccount:app.activeAccount];
        
        metadataNet.action = actionReadFolder;
        metadataNet.date = [NSDate date];
        metadataNet.directoryID = directoryID;
        metadataNet.priority = NSOperationQueuePriorityHigh;
        metadataNet.selector = selectorReadFolder;
        metadataNet.serverUrl = serverUrl;

        [app addNetworkingOperationQueue:app.netQueue delegate:self metadataNet:metadataNet];
        
    }
}

#pragma mark -
#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Search =====
#pragma --------------------------------------------------------------------------------------------

-(void)updateSearchResultsForSearchController:(UISearchController *)searchController
{
    _isSearchMode = YES;
    [self deleteRefreshControl];
    
    NSString *fileName = [CCUtility removeForbiddenCharactersServer:searchController.searchBar.text];
    
    if (fileName.length >= k_minCharsSearch && [fileName isEqualToString:_searchFileName] == NO) {
        
        _searchFileName = fileName;
        
        if ([[NCManageDatabase sharedInstance] getServerVersionAccount:app.activeAccount] >= 12 && ![_depth isEqualToString:@"0"]) {
            
            [[CCActions sharedInstance] search:_serverUrl fileName:_searchFileName depth:_depth delegate:self];
            
            _noFilesSearchTitle = @"";
            _noFilesSearchDescription = NSLocalizedString(@"_search_in_progress_", nil);
        
            [self.tableView reloadEmptyDataSet];

        } else {
            
            NSString *directoryID = [CCCoreData getDirectoryIDFromServerUrl:_serverUrl activeAccount:app.activeAccount];
            NSPredicate *predicate = [NSPredicate predicateWithFormat:@"(directoryID == %@) AND (account == %@) AND (fileNamePrint CONTAINS[cd] %@)", directoryID, app.activeAccount, fileName];
            NSArray *records = [CCCoreData getTableMetadataWithPredicate:predicate context:nil];
            
            [_searchResultMetadatas removeAllObjects];
            for (TableMetadata *record in records)
                [_searchResultMetadatas addObject:[CCCoreData insertEntityInMetadata:record]];
            
            CCMetadataNet *metadataNet = [[CCMetadataNet alloc] initWithAccount:app.activeAccount];
            
            metadataNet.account = app.activeAccount;
            metadataNet.action = actionUploadTemplate;
            metadataNet.directoryID = directoryID;
            metadataNet.selector = selectorSearch;
            metadataNet.serverUrl = _serverUrl;

            [self readFolderSuccess:metadataNet permissions:@"" etag:@"" metadatas:_searchResultMetadatas];
        }
    }
    
    if (_searchResultMetadatas.count == 0 && fileName.length == 0) {

        [self reloadDatasource];
    }
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar
{
    [self cancelSearchBar];
    
    [self readFolderWithForced:NO serverUrl:_serverUrl];
}

- (void)searchFailure:(CCMetadataNet *)metadataNet message:(NSString *)message errorCode:(NSInteger)errorCode
{
    _searchFileName = @"";

    if (message)
        [app messageNotification:@"_error_" description:message visible:YES delay:k_dismissAfterSecond type:TWMessageBarMessageTypeError errorCode:errorCode];
}

- (void)searchSuccess:(CCMetadataNet *)metadataNet metadatas:(NSArray *)metadatas
{
    _searchResultMetadatas = [[NSMutableArray alloc] initWithArray:metadatas];
    
    [self readFolderSuccess:metadataNet permissions:nil etag:nil metadatas:metadatas];
}

- (void)cancelSearchBar
{
    if (self.searchController.active) {
        
        [self.searchController setActive:NO];
        [self createRefreshControl];
    
        _isSearchMode = NO;
        _searchFileName = @"";
        _dateReadDataSource = nil;
        _searchResultMetadatas = [NSMutableArray new];
        
        [self reloadDatasource];
    }
}

- (void)searchBar:(UISearchBar *)searchBar selectedScopeButtonIndexDidChange:(NSInteger)selectedScope
{
    NSString *title = [self.searchController.searchBar.scopeButtonTitles objectAtIndex:selectedScope];
    self.searchController.searchBar.placeholder = title;

    if ([title isEqualToString:NSLocalizedString(@"_search_this_folder_",nil)])
        _depth = @"0";
    
    if ([title isEqualToString:NSLocalizedString(@"_search_sub_folder_",nil)])
        _depth = @"1";
    
    if ([title isEqualToString:NSLocalizedString(@"_search_all_folders_",nil)])
        _depth = @"infinity";
    
    _searchFileName = @"";
    [self updateSearchResultsForSearchController:self.searchController];
}

#pragma mark -
#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Delete File or Folder =====
#pragma --------------------------------------------------------------------------------------------

- (void)deleteFileOrFolderFailure:(CCMetadataNet *)metadataNet message:(NSString *)message errorCode:(NSInteger)errorCode
{
    [self deleteFileOrFolderSuccess:metadataNet]; 
}

- (void)deleteFileOrFolderSuccess:(CCMetadataNet *)metadataNet
{
    [_queueSelector removeObject:metadataNet.selector];
    
    if ([_queueSelector count] == 0) {
        
        [_hud hideHud];
        
        if (_isSearchMode)
            [self readFolderWithForced:YES serverUrl:metadataNet.serverUrl];
        else
            [self reloadDatasource:metadataNet.serverUrl fileID:metadataNet.metadata.fileID selector:metadataNet.selector];
        
        // next
        if ([_selectedMetadatas count] > 0) {
            
            [_selectedMetadatas removeObjectAtIndex:0];
            
            if ([_selectedMetadatas count] > 0)
                [self deleteFileOrFolder:[_selectedMetadatas objectAtIndex:0] numFile:[_selectedMetadatas count] ofFile:_numSelectedMetadatas];
        }
    }
}

- (void)deleteFileOrFolder:(CCMetadata *)metadata numFile:(NSInteger)numFile ofFile:(NSInteger)ofFile
{
    if (metadata.cryptated) {
        [_queueSelector addObject:selectorDeleteCrypto];
        [_queueSelector addObject:selectorDeletePlist];
    } else {
        [_queueSelector addObject:selectorDelete];
    }
    
    [[CCActions sharedInstance] deleteFileOrFolder:metadata delegate:self];
        
    [_hud visibleHudTitle:[NSString stringWithFormat:NSLocalizedString(@"_delete_file_n_", nil), ofFile - numFile + 1, ofFile] mode:MBProgressHUDModeIndeterminate color:nil];
}

- (void)deleteSelectionFile
{
    [_selectedMetadatas removeAllObjects];
    [_queueSelector removeAllObjects];
    
    _selectedMetadatas = [[NSMutableArray alloc] initWithArray: [self getMetadatasFromSelectedRows:[self.tableView indexPathsForSelectedRows]]];
    _numSelectedMetadatas = [_selectedMetadatas count];
    
    if ([_selectedMetadatas count] > 0)
        [self deleteFileOrFolder:[_selectedMetadatas objectAtIndex:0] numFile:[_selectedMetadatas count] ofFile:_numSelectedMetadatas];
    
    [self tableViewSelect:NO];
}

- (void)deleteFile
{
    [_selectedMetadatas removeAllObjects];
    [_queueSelector removeAllObjects];
    _numSelectedMetadatas = 1;
    
    [_selectedMetadatas addObject:_metadata];
    
    if ([_selectedMetadatas count] > 0)
        [self deleteFileOrFolder:[_selectedMetadatas objectAtIndex:0] numFile:[_selectedMetadatas count] ofFile:_numSelectedMetadatas];
    
    [self tableViewSelect:NO];
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Rename / Move =====
#pragma --------------------------------------------------------------------------------------------

- (void)renameSuccess:(CCMetadataNet *)metadataNet
{
    [self readFolderWithForced:YES serverUrl:metadataNet.serverUrl];
}

- (void)renameFile:(CCMetadata *)metadata fileName:(NSString *)fileName
{
    [[CCActions sharedInstance] renameFileOrFolder:metadata fileName:fileName delegate:self];
}

- (void)renameNote:(CCMetadata *)metadata fileName:(NSString *)fileName
{
    CCTemplates *templates = [[CCTemplates alloc] init];
    
    NSMutableDictionary *field = [[CCCrypto sharedManager] getDictionaryEncrypted:metadata.fileName uuid:metadata.uuid isLocal:NO directoryUser:app.directoryUser];
    NSString *fileNameModel = [templates salvaNote:[field objectForKey:@"note"] titolo:fileName fileName:metadata.fileName uuid:metadata.uuid];
    
    if (fileNameModel) {
        
        CCMetadataNet *metadataNet = [[CCMetadataNet alloc] initWithAccount:app.activeAccount];
        
        
        metadataNet.action = actionUploadTemplate;
        metadataNet.fileName = [CCUtility trasformedFileNamePlistInCrypto:fileNameModel];
        metadataNet.fileNamePrint = fileName;
        metadataNet.rev = metadata.rev;
        metadataNet.serverUrl = [CCCoreData getServerUrlFromDirectoryID:metadata.directoryID activeAccount:metadata.account];
        metadataNet.session = k_upload_session_foreground;
        metadataNet.taskStatus = k_taskStatusResume;
        
        if ([CCCoreData isOfflineLocalFileID:metadata.fileID activeAccount:app.activeAccount])
            metadataNet.selectorPost = selectorAddOffline;
        
        [app addNetworkingOperationQueue:app.netQueue delegate:self metadataNet:metadataNet];
    }
}

- (void)renameMoveFileOrFolderFailure:(CCMetadataNet *)metadataNet message:(NSString *)message errorCode:(NSInteger)errorCode
{
    if ([metadataNet.selector isEqualToString:selectorMove]) {
        
        [_hud hideHud];
    
        if (message)
            [app messageNotification:@"_move_" description:message visible:YES delay:k_dismissAfterSecond type:TWMessageBarMessageTypeError errorCode:errorCode];
        
        [_selectedMetadatas removeAllObjects];
        [_queueSelector removeAllObjects];
    }
}

- (void)moveSuccess:(CCMetadataNet *)metadataNet revTo:(NSString *)revTo
{
    [_queueSelector removeObject:metadataNet.selector];
    
    if ([_queueSelector count] == 0) {
    
        [_hud hideHud];
        
        NSString *fileName = [CCUtility trasformedFileNameCryptoInPlist:metadataNet.fileName];
        NSString *directoryID = metadataNet.directoryID;
        NSString *directoryIDTo = metadataNet.directoryIDTo;
        
        NSString *serverUrlTo = [CCCoreData getServerUrlFromDirectoryID:directoryIDTo activeAccount:app.activeAccount];

        // FILE -> Metadata
        if (metadataNet.directory == NO) {
            
            // move metadata
            [CCCoreData moveMetadata:fileName directoryID:directoryID directoryIDTo:directoryIDTo activeAccount:app.activeAccount];
        }
    
        // DIRECTORY ->  Directory - CCMetadata
        if (metadataNet.directory == YES) {
        
            // delete all dir / subdir
            NSArray *directoryIDs = [CCCoreData deleteDirectoryAndSubDirectory:[CCUtility stringAppendServerUrl:metadataNet.serverUrl addFileName:fileName] activeAccount:app.activeAccount];
        
            // delete all metadata and local file in dir / subdir
            for (NSString *directoryIDDelete in directoryIDs)
                [CCCoreData deleteMetadataWithPredicate:[NSPredicate predicateWithFormat:@"(directoryID == %@)AND (account == %@)",directoryIDDelete, app.activeAccount]];
        
            // move metadata
            [CCCoreData moveMetadata:fileName directoryID:directoryID directoryIDTo:directoryIDTo activeAccount:app.activeAccount];
            
            // Add new directory
            NSString *newDirectory = [NSString stringWithFormat:@"%@/%@", serverUrlTo, fileName];
            [CCCoreData addDirectory:newDirectory permissions:nil activeAccount:app.activeAccount];
            
            // Check Offline
            if ([CCCoreData isOfflineDirectoryServerUrl:serverUrlTo activeAccount:app.activeAccount])
                [CCCoreData setOfflineDirectoryServerUrl:newDirectory offline:YES activeAccount:app.activeAccount];
        }
    
        // reload Datasource
        if ([metadataNet.selectorPost isEqualToString:selectorReadFolderForced] || _isSearchMode)
            [self readFolderWithForced:YES serverUrl:metadataNet.serverUrl];
        else
            [self reloadDatasource];

        // Next file
        [_selectedMetadatas removeObjectAtIndex:0];
        [self performSelectorOnMainThread:@selector(moveFileOrFolder:) withObject:metadataNet.serverUrlTo waitUntilDone:NO];
    }
}

- (void)moveFileOrFolder:(NSString *)serverUrlTo
{
    if ([_selectedMetadatas count] > 0) {
        
        CCMetadata *metadata = [_selectedMetadatas objectAtIndex:0];
        
        // Plain
        if (metadata.cryptated == NO) {
            
            OCnetworking *ocNetworking = [[OCnetworking alloc] initWithDelegate:nil metadataNet:nil withUser:app.activeUser withPassword:app.activePassword withUrl:app.activeUrl isCryptoCloudMode:NO];
            
            NSError *error = [ocNetworking readFileSync:[NSString stringWithFormat:@"%@/%@", serverUrlTo, metadata.fileName]];
            
            if(!error) {
                
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                    
                    UIAlertController * alert= [UIAlertController alertControllerWithTitle:NSLocalizedString(@"_error_", nil) message:NSLocalizedString(@"_file_already_exists_", nil) preferredStyle:UIAlertControllerStyleAlert];
                    UIAlertAction* ok = [UIAlertAction actionWithTitle:NSLocalizedString(@"_ok_", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
                    }];
                    [alert addAction:ok];
                    [self presentViewController:alert animated:YES completion:nil];
                });
                
                return;
            }
            
            CCMetadataNet *metadataNet = [[CCMetadataNet alloc] initWithAccount:app.activeAccount];
            
            metadataNet.action = actionMoveFileOrFolder;
            metadataNet.directory = metadata.directory;
            metadataNet.fileID = metadata.fileID;
            metadataNet.directoryID = metadata.directoryID;
            metadataNet.directoryIDTo = [CCCoreData getDirectoryIDFromServerUrl:serverUrlTo activeAccount:app.activeAccount];
            metadataNet.fileName = metadata.fileName;
            metadataNet.fileNamePrint = metadataNet.fileNamePrint;
            metadataNet.fileNameTo = metadata.fileName;
            metadataNet.rev = metadata.rev;
            metadataNet.selector = selectorMove;
            metadataNet.serverUrl = [CCCoreData getServerUrlFromDirectoryID:metadata.directoryID activeAccount:metadata.account];
            metadataNet.serverUrlTo = serverUrlTo;
            
            [_queueSelector addObject:metadataNet.selector];
            
            [app addNetworkingOperationQueue:app.netQueue delegate:self metadataNet:metadataNet];
        }
        
        // cyptated
        if (metadata.cryptated == YES) {
            
            CCMetadataNet *metadataNet = [[CCMetadataNet alloc] initWithAccount:app.activeAccount];
            
            metadataNet.action = actionMoveFileOrFolder;
            metadataNet.directory = metadata.directory;
            metadataNet.fileID = metadata.fileID;
            metadataNet.directoryID = metadata.directoryID;
            metadataNet.directoryIDTo = [CCCoreData getDirectoryIDFromServerUrl:serverUrlTo activeAccount:app.activeAccount];
            metadataNet.fileNamePrint = metadata.fileNamePrint;
            metadataNet.rev = metadata.rev;
            metadataNet.serverUrl = [CCCoreData getServerUrlFromDirectoryID:metadata.directoryID activeAccount:metadata.account];
            metadataNet.serverUrlTo = serverUrlTo;
            
            // data
            metadataNet.fileName = metadata.fileNameData;
            metadataNet.fileNameTo = metadata.fileNameData;
            metadataNet.selector = selectorMoveCrypto;
            
            [_queueSelector addObject:metadataNet.selector];
            [app addNetworkingOperationQueue:app.netQueue delegate:self metadataNet:metadataNet];
            
            // plist
            metadataNet.fileName = metadata.fileName;
            metadataNet.fileNameTo = metadata.fileName;
            metadataNet.selector = selectorMovePlist;
            
            [_queueSelector addObject:metadataNet.selector];
            [app addNetworkingOperationQueue:app.netQueue delegate:self metadataNet:metadataNet];
        }
        
        [_hud visibleHudTitle:[NSString stringWithFormat:NSLocalizedString(@"_move_file_n_", nil), _numSelectedMetadatas - [_selectedMetadatas count] + 1, _numSelectedMetadatas] mode:MBProgressHUDModeIndeterminate color:nil];
    }
}

- (void)moveServerUrlTo:(NSString *)serverUrlTo title:(NSString *)title selectedMetadatas:(NSArray *)selectedMetadatas
{
    [_selectedMetadatas removeAllObjects];
    [_queueSelector removeAllObjects];
    
    _selectedMetadatas = [[NSMutableArray alloc] initWithArray:selectedMetadatas];
    _numSelectedMetadatas = [_selectedMetadatas count];
    
    [self performSelectorOnMainThread:@selector(moveFileOrFolder:) withObject:serverUrlTo waitUntilDone:NO];
    [self tableViewSelect:NO];
}

- (void)moveOpenWindow:(NSArray *)indexPaths
{
    UINavigationController* navigationController = [[UIStoryboard storyboardWithName:@"CCMove" bundle:nil] instantiateViewControllerWithIdentifier:@"CCMove"];
    
    CCMove *viewController = (CCMove *)navigationController.topViewController;

    viewController.delegate = self;
    viewController.move.title = NSLocalizedString(@"_move_", nil);
    viewController.selectedMetadatas = [self getMetadatasFromSelectedRows:indexPaths];
    viewController.tintColor = [NCBrandColor sharedInstance].navigationBarText;
    viewController.barTintColor = [NCBrandColor sharedInstance].brand;
    viewController.tintColorTitle = [NCBrandColor sharedInstance].navigationBarText;
    viewController.networkingOperationQueue = app.netQueue;
    
    [navigationController setModalPresentationStyle:UIModalPresentationFormSheet];
    [self presentViewController:navigationController animated:YES completion:nil];
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Create folder =====
#pragma --------------------------------------------------------------------------------------------

- (void)createFolderFailure:(CCMetadataNet *)metadataNet message:(NSString *)message errorCode:(NSInteger)errorCode
{
    [_hud hideHud];
    
    if (message)
        [app messageNotification:@"_create_folder_" description:message visible:YES delay:k_dismissAfterSecond type:TWMessageBarMessageTypeError errorCode:errorCode];
}

- (void)createFolderSuccess:(CCMetadataNet *)metadataNet
{
    [_hud hideHud];
    
    NSString *newDirectory = [NSString stringWithFormat:@"%@/%@", metadataNet.serverUrl, metadataNet.fileName];
    
    [CCCoreData addDirectory:newDirectory permissions:nil activeAccount:app.activeAccount];
    
    // Check Offline
    if ([CCCoreData isOfflineDirectoryServerUrl:_serverUrl activeAccount:app.activeAccount])
        [CCCoreData setOfflineDirectoryServerUrl:newDirectory offline:YES activeAccount:app.activeAccount];
    
    // Load Folder or the Datasource
    if ([metadataNet.selectorPost isEqualToString:selectorReadFolderForced]) {
        [self readFolderWithForced:YES serverUrl:metadataNet.serverUrl];
    } else {
        [self reloadDatasource:metadataNet.serverUrl fileID:metadataNet.fileID selector:metadataNet.selector];
    }
}

- (void)createFolder:(NSString *)fileNameFolder folderCameraUpload:(BOOL)folderCameraUpload
{
    CCMetadataNet *metadataNet = [[CCMetadataNet alloc] initWithAccount:app.activeAccount];
    
    fileNameFolder = [CCUtility removeForbiddenCharactersServer:fileNameFolder];
    if (![fileNameFolder length]) return;
    
    //if (folderCameraUpload) metadataNet.serverUrl = [CCCoreData getCameraUploadFolderPathActiveAccount:app.activeAccount activeUrl:app.activeUrl];
    if (folderCameraUpload) metadataNet.serverUrl = [[NCManageDatabase sharedInstance] getAccountsCameraUploadFolderPath:app.activeAccount activeUrl:app.activeUrl];
    else  metadataNet.serverUrl = _serverUrl;
    
    metadataNet.action = actionCreateFolder;
    if (folderCameraUpload)
        metadataNet.options = @"folderCameraUpload";
    metadataNet.fileName = fileNameFolder;
    metadataNet.selector = selectorCreateFolder;
    metadataNet.selectorPost = selectorReadFolderForced;
    
    [app addNetworkingOperationQueue:app.netQueue delegate:self metadataNet:metadataNet];
    
    if (!folderCameraUpload)
        [_hud visibleHudTitle:NSLocalizedString(@"_create_folder_", nil) mode:MBProgressHUDModeIndeterminate color:nil];
}

- (void)createFolderEncrypted:(NSString *)fileNameFolder
{
    CCMetadataNet *metadataNet = [[CCMetadataNet alloc] initWithAccount:app.activeAccount];
    NSString *fileNamePlist;
    
    fileNameFolder = [CCUtility removeForbiddenCharactersServer:fileNameFolder];
    if (![fileNameFolder length]) return;
    
    NSString *title = [AESCrypt encrypt:fileNameFolder password:[[CCCrypto sharedManager] getKeyPasscode:[CCUtility getUUID]]];

    fileNamePlist =  [[CCCrypto sharedManager] createFilenameEncryptor:fileNameFolder uuid:[CCUtility getUUID]];
    
    [[CCCrypto sharedManager] createFilePlist:[NSTemporaryDirectory() stringByAppendingString:fileNamePlist] title:title len:0 directory:true uuid:[CCUtility getUUID] nameCurrentDevice:[CCUtility getNameCurrentDevice] icon:@""];
    
    // Create folder
    metadataNet.action = actionCreateFolder;
    metadataNet.fileName = fileNamePlist;
    metadataNet.priority = NSOperationQueuePriorityVeryHigh;
    metadataNet.selector = selectorCreateFolder;
    metadataNet.serverUrl = _serverUrl;
    
    [app addNetworkingOperationQueue:app.netQueue delegate:self metadataNet:metadataNet];
    
    // upload plist file
    metadataNet.action = actionUploadOnlyPlist;
    metadataNet.fileName = [fileNamePlist stringByAppendingString:@".plist"];
    metadataNet.priority = NSOperationQueuePriorityVeryLow;
    metadataNet.selectorPost = selectorReadFolderForced;
    metadataNet.serverUrl = _serverUrl;
    metadataNet.session = k_upload_session_foreground;
    metadataNet.taskStatus = k_taskStatusResume;
    
    [app addNetworkingOperationQueue:app.netQueue delegate:self metadataNet:metadataNet];
    
    [_hud visibleHudTitle:NSLocalizedString(@"_create_folder_", nil) mode:MBProgressHUDModeIndeterminate color:nil];
}

- (void)createFolderCameraUpload
{
    NSString *cameraFolderName = [[NCManageDatabase sharedInstance] getAccountsCameraUploadFolderName:app.activeAccount activeUrl:nil];

    [self createFolder:cameraFolderName folderCameraUpload:YES];

    //[self createFolder:[CCCoreData getCameraUploadFolderNameActiveAccount:app.activeAccount] folderCameraUpload:YES];
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark =====  Encrypted / Decrypted Folder =====
#pragma --------------------------------------------------------------------------------------------

- (void)encyptedDecryptedFolder
{
    NSString *serverUrl = [CCCoreData getServerUrlFromDirectoryID:_metadata.directoryID activeAccount:_metadata.account];
    
    if (_metadata.cryptated) {
        
        // DECRYPTED
        
        CCMetadataNet *metadataNet = [[CCMetadataNet alloc] initWithAccount:app.activeAccount];
        
        //-------------------------- RENAME -------------------------------------------//
        
        metadataNet.action = actionMoveFileOrFolder;
        metadataNet.fileID = _metadata.fileID;
        metadataNet.fileName = _metadata.fileNameData;
        metadataNet.fileNameTo = _metadata.fileNamePrint;
        metadataNet.fileNamePrint = _metadata.fileNamePrint;
        metadataNet.priority = NSOperationQueuePriorityVeryHigh;
        metadataNet.selector = selectorRename;
        metadataNet.serverUrl = serverUrl;
        metadataNet.serverUrlTo = serverUrl;
        
        [app addNetworkingOperationQueue:app.netQueue delegate:self metadataNet:metadataNet];
        
        //-------------------------- DELETE -------------------------------------------//
        
        metadataNet.action = actionDeleteFileDirectory;
        metadataNet.fileID = _metadata.fileID;
        metadataNet.fileName = _metadata.fileName;
        metadataNet.fileNamePrint = _metadata.fileNamePrint;
        metadataNet.priority = NSOperationQueuePriorityVeryLow;
        metadataNet.selector = selectorDeletePlist;
        metadataNet.selectorPost = selectorReadFolderForced;
        
        [app addNetworkingOperationQueue:app.netQueue delegate:self metadataNet:metadataNet];
        
    } else {
                
        // ENCRYPTED
        
        CCMetadataNet *metadataNet = [[CCMetadataNet alloc] initWithAccount:app.activeAccount];
        
        // Create File Plist
        NSString *fileNameCrypto = [[CCCrypto sharedManager] createFileDirectoryPlist:_metadata];
        
        //-------------------------- RENAME -------------------------------------------//
        
        metadataNet.action = actionMoveFileOrFolder;
        metadataNet.fileID = _metadata.fileID;
        metadataNet.fileName = _metadata.fileName;
        metadataNet.fileNamePrint = _metadata.fileNamePrint;
        metadataNet.fileNameTo = fileNameCrypto;
        metadataNet.priority = NSOperationQueuePriorityVeryHigh;
        metadataNet.selector = selectorRename;
        metadataNet.serverUrl = serverUrl;
        metadataNet.serverUrlTo = serverUrl;
        
        [app addNetworkingOperationQueue:app.netQueue delegate:self metadataNet:metadataNet];
        
        //-------------------------- UPLOAD -------------------------------------------//
        
        metadataNet.action = actionUploadOnlyPlist;
        metadataNet.fileName = [fileNameCrypto stringByAppendingString:@".plist"];
        metadataNet.priority = NSOperationQueuePriorityVeryLow;
        metadataNet.selectorPost = selectorReadFolderForced;
        metadataNet.serverUrl = serverUrl;
        metadataNet.session = k_upload_session_foreground;
        metadataNet.taskStatus = k_taskStatusResume;
        
        [app addNetworkingOperationQueue:app.netQueue delegate:self metadataNet:metadataNet];
    }
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Encrypted/Decrypted File =====
#pragma --------------------------------------------------------------------------------------------

- (void)encryptedSelectedFiles
{
    NSMutableArray *metadatas = [[NSMutableArray alloc] init];
    
    NSArray *selectedMetadatas = [self getMetadatasFromSelectedRows:[self.tableView indexPathsForSelectedRows]];
    
    for (CCMetadata *metadata in selectedMetadatas) {
        if (metadata.cryptated == NO && metadata.directory == NO)
            [metadatas addObject:metadata];
    }
    
    if ([metadatas count] > 0) {
        
        NSLog(@"[LOG] Start encrypted selected files ...");
    
        for (CCMetadata* metadata in metadatas) {
            
            NSString *serverUrl = [CCCoreData getServerUrlFromDirectoryID:metadata.directoryID activeAccount:metadata.account];
            
            [[CCNetworking sharedNetworking] downloadFile:metadata serverUrl:serverUrl downloadData:YES downloadPlist:NO selector:selectorEncryptFile selectorPost:nil session:k_download_session taskStatus: k_taskStatusResume delegate:self];
        }
    }
    
    [self tableViewSelect:NO];
}

- (void)decryptedSelectedFiles
{
    NSMutableArray *metadatas = [[NSMutableArray alloc] init];
    
    NSArray *selectedMetadatas = [self getMetadatasFromSelectedRows:[self.tableView indexPathsForSelectedRows]];
    
    for (CCMetadata *metadata in selectedMetadatas) {
        if (metadata.cryptated == YES && metadata.directory == NO && [metadata.model length] == 0)
            [metadatas addObject:metadata];
    }
    
    if ([metadatas count] > 0) {
        
        NSLog(@"[LOG] Start decrypted selected files ...");
        
        for (CCMetadata* metadata in metadatas) {
            
            NSString *serverUrl = [CCCoreData getServerUrlFromDirectoryID:metadata.directoryID activeAccount:metadata.account];
            
            [[CCNetworking sharedNetworking] downloadFile:metadata serverUrl:serverUrl downloadData:YES downloadPlist:NO selector:selectorDecryptFile selectorPost:nil session:k_download_session taskStatus: k_taskStatusResume delegate:self];
        }
    }
    
    [self tableViewSelect:NO];
}

- (void)cmdEncryptedDecryptedFile
{
    NSString *selector;
    
    if (_metadata.cryptated == YES) selector = selectorDecryptFile;
    if (_metadata.cryptated == NO) selector = selectorEncryptFile;
    
    NSString *serverUrl = [CCCoreData getServerUrlFromDirectoryID:_metadata.directoryID activeAccount:_metadata.account];
    
    [[CCNetworking sharedNetworking] downloadFile:_metadata serverUrl:serverUrl downloadData:YES downloadPlist:NO selector:selector selectorPost:nil session:k_download_session taskStatus:k_taskStatusResume delegate:self];
}

- (void)encryptedFile:(CCMetadata *)metadata
{
    NSString *fileNameFrom = [NSString stringWithFormat:@"%@/%@", app.directoryUser, metadata.fileID];
    NSString *fileNameTo = [NSString stringWithFormat:@"%@/%@", app.directoryUser, metadata.fileNamePrint];
    [[NSFileManager defaultManager] copyItemAtPath:fileNameFrom toPath:fileNameTo error:nil];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:fileNameTo]) {
        
        NSString *serverUrl = [CCCoreData getServerUrlFromDirectoryID:metadata.directoryID activeAccount:app.activeAccount];
                
        dispatch_async(dispatch_get_main_queue(), ^{
            [[CCNetworking sharedNetworking] uploadFile:metadata.fileName serverUrl:serverUrl cryptated:YES onlyPlist:NO session:k_upload_session taskStatus:k_taskStatusResume selector:nil selectorPost:nil errorCode:0 delegate:nil];
            [self performSelector:@selector(reloadDatasource) withObject:nil];
        });
        
    } else {
            
        [app messageNotification:@"_encrypted_selected_files_" description:@"_file_not_present_" visible:YES delay:k_dismissAfterSecond type:TWMessageBarMessageTypeError errorCode:0];
    }
}

- (void)decryptedFile:(CCMetadata *)metadata
{
    NSString *fileNameFrom = [NSString stringWithFormat:@"%@/%@", app.directoryUser, metadata.fileID];
    NSString *fileNameTo = [NSString stringWithFormat:@"%@/%@", app.directoryUser, metadata.fileNamePrint];
        
    [[NSFileManager defaultManager] copyItemAtPath:fileNameFrom toPath:fileNameTo error:nil];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:fileNameTo]) {
        
        NSString *serverUrl = [CCCoreData getServerUrlFromDirectoryID:metadata.directoryID activeAccount:app.activeAccount];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [[CCNetworking sharedNetworking] uploadFile:metadata.fileNamePrint serverUrl:serverUrl cryptated:NO onlyPlist:NO session:k_upload_session taskStatus:k_taskStatusResume selector:nil selectorPost:nil errorCode:0 delegate:nil];
            [self performSelector:@selector(reloadDatasource) withObject:nil];
        });
        
    } else {
            
        [app messageNotification:@"_decrypted_selected_files_" description:@"_file_not_present_" visible:YES delay:k_dismissAfterSecond type:TWMessageBarMessageTypeError errorCode:0];
    }
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Progress & Task Button =====
#pragma --------------------------------------------------------------------------------------------

- (void)triggerProgressTask:(NSNotification *)notification
{
    NSDictionary *dict = notification.userInfo;
    NSString *fileID = [dict valueForKey:@"fileID"];
    NSString *serverUrl = [dict valueForKey:@"serverUrl"];
    BOOL cryptated = [[dict valueForKey:@"cryptated"] boolValue];
    float progress = [[dict valueForKey:@"progress"] floatValue];
    
    // Check
    if (!fileID)
        return;
    
    [app.listProgressMetadata setObject:[NSNumber numberWithFloat:progress] forKey:fileID];
    
    if (![serverUrl isEqualToString:_serverUrl])
        return;
    
    NSIndexPath *indexPath = [_sectionDataSource.fileIDIndexPath objectForKey:fileID];
    
    if (indexPath) {
        
        CCTransfersCell *cell = (CCTransfersCell *)[self.tableView cellForRowAtIndexPath:indexPath];
        
        if (cryptated) cell.progressView.progressTintColor = [NCBrandColor sharedInstance].cryptocloud;
        else cell.progressView.progressTintColor = [UIColor blackColor];
        
        cell.progressView.hidden = NO;
        [cell.progressView setProgress:progress];
    }
        
    if (progress == 0)
        [self.navigationController cancelCCProgress];
    else
        [self.navigationController setCCProgressPercentage:progress*100 andTintColor: [NCBrandColor sharedInstance].navigationBarProgress];
}

- (void)reloadTaskButton:(id)sender withEvent:(UIEvent *)event
{
    UITouch * touch = [[event allTouches] anyObject];
    CGPoint location = [touch locationInView:self.tableView];
    NSIndexPath * indexPath = [self.tableView indexPathForRowAtPoint:location];
    
    if (indexPath) {
        
        CCMetadata *metadata = [self getMetadataFromSectionDataSource:indexPath];
        
        if (metadata)
            [self reloadTaskButton:metadata];
    }
}

- (void)reloadTaskButton:(CCMetadata *)metadata
{
    NSURLSession *session = [[CCNetworking sharedNetworking] getSessionfromSessionDescription:metadata.session];
    __block NSURLSessionTask *findTask;
    
    // DOWNLOAD
    if ([metadata.session length] > 0 && [metadata.session containsString:@"download"]) {
        
        [session getTasksWithCompletionHandler:^(NSArray *dataTasks, NSArray *uploadTasks, NSArray *downloadTasks) {
            
            for (NSURLSessionUploadTask *task in downloadTasks)
                if (task.taskIdentifier == metadata.sessionTaskIdentifier || task.taskIdentifier == metadata.sessionTaskIdentifierPlist) {
                    findTask = task;
                    [app.listChangeTask setObject:@"reloadDownload" forKey:metadata.fileID];
                    [task cancel];
                }
            
            if (!findTask) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [app.listChangeTask setObject:@"reloadDownload" forKey:metadata.fileID];
                    NSArray *object = [[NSArray alloc] initWithObjects:session, metadata, findTask, nil];
                    [[NSNotificationCenter defaultCenter] postNotificationName:k_networkingSessionNotification object:object];
                });
            }
        }];
    }

    // UPLOAD
    if ([metadata.session length] > 0 && [metadata.session containsString:@"upload"]) {
        
        [session getTasksWithCompletionHandler:^(NSArray *dataTasks, NSArray *uploadTasks, NSArray *downloadTasks) {
            
            for (NSURLSessionUploadTask *task in uploadTasks)
                if (task.taskIdentifier == metadata.sessionTaskIdentifier || task.taskIdentifier == metadata.sessionTaskIdentifierPlist) {
                    findTask = task;
                    [app.listChangeTask setObject:@"reloadUpload" forKey:metadata.fileID];
                    [task cancel];
                }
            
            if (!findTask) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [app.listChangeTask setObject:@"reloadUpload" forKey:metadata.fileID];
                    NSArray *object = [[NSArray alloc] initWithObjects:session, metadata, findTask, nil];
                    [[NSNotificationCenter defaultCenter] postNotificationName:k_networkingSessionNotification object:object];
                });
            }
        }];
    }
}

- (void)cancelTaskButton:(id)sender withEvent:(UIEvent *)event
{
    UITouch * touch = [[event allTouches] anyObject];
    CGPoint location = [touch locationInView:self.tableView];
    NSIndexPath * indexPath = [self.tableView indexPathForRowAtPoint:location];
    
    if (indexPath) {
        
        CCMetadata *metadata = [self getMetadataFromSectionDataSource:indexPath];
        
        if (metadata)
            [self cancelTaskButton:metadata reloadTable:YES];
    }
}

- (void)cancelTaskButton:(CCMetadata *)metadata reloadTable:(BOOL)reloadTable
{
    NSURLSession *session = [[CCNetworking sharedNetworking] getSessionfromSessionDescription:metadata.session];
    __block NSURLSessionTask *findTask;

    // DOWNLOAD
    if ([metadata.session length] > 0 && [metadata.session containsString:@"download"]) {
        
        [session getTasksWithCompletionHandler:^(NSArray *dataTasks, NSArray *uploadTasks, NSArray *downloadTasks) {
            
            for (NSURLSessionTask *task in downloadTasks)
                if (task.taskIdentifier == metadata.sessionTaskIdentifier || task.taskIdentifier == metadata.sessionTaskIdentifierPlist) {
                    findTask = task;
                    [app.listChangeTask setObject:@"cancelDownload" forKey:metadata.fileID];
                    [task cancel];
                }
            
            if (!findTask) {
                [app.listChangeTask setObject:@"cancelDownload" forKey:metadata.fileID];
                NSArray *object = [[NSArray alloc] initWithObjects:session, metadata, findTask, nil];
                [[NSNotificationCenter defaultCenter] postNotificationName:k_networkingSessionNotification object:object];
            }
        }];
    }

    // UPLOAD
    if ([metadata.session length] > 0 && [metadata.session containsString:@"upload"]) {
        
        [session getTasksWithCompletionHandler:^(NSArray *dataTasks, NSArray *uploadTasks, NSArray *downloadTasks) {
            
            for (NSURLSessionUploadTask *task in uploadTasks)
                if (task.taskIdentifier == metadata.sessionTaskIdentifier ||  task.taskIdentifier == metadata.sessionTaskIdentifierPlist) {
                    findTask = task;
                    [app.listChangeTask setObject:@"cancelUpload" forKey:metadata.fileID];
                    [task cancel];
                }
            
            if (!findTask) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [app.listChangeTask setObject:@"cancelUpload" forKey:metadata.fileID];
                    NSArray *object = [[NSArray alloc] initWithObjects:session, metadata, findTask, nil];
                    [[NSNotificationCenter defaultCenter] postNotificationName:k_networkingSessionNotification object:object];
                });
            }
        }];
    }
}

- (void)stopTaskButton:(id)sender withEvent:(UIEvent *)event
{
    UITouch * touch = [[event allTouches] anyObject];
    CGPoint location = [touch locationInView:self.tableView];
    NSIndexPath * indexPath = [self.tableView indexPathForRowAtPoint:location];
    
    if (indexPath) {
        
        CCMetadata *metadata = [self getMetadataFromSectionDataSource:indexPath];
        
        if (metadata)
            [self stopTaskButton:metadata];
    }
}

- (void)stopTaskButton:(CCMetadata *)metadata
{
    NSURLSession *session = [[CCNetworking sharedNetworking] getSessionfromSessionDescription:metadata.session];
    __block NSURLSessionTask *findTask;

    // UPLOAD
    if ([metadata.session length] > 0 && [metadata.session containsString:@"upload"]) {
        
        [session getTasksWithCompletionHandler:^(NSArray *dataTasks, NSArray *uploadTasks, NSArray *downloadTasks) {
            
            for (NSURLSessionUploadTask *task in uploadTasks)
                if (task.taskIdentifier == metadata.sessionTaskIdentifier || task.taskIdentifier == metadata.sessionTaskIdentifierPlist) {                    
                    [app.listChangeTask setObject:@"stopUpload" forKey:metadata.fileID];
                    findTask = task;
                    [task cancel];
                }
            
            if (!findTask) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [app.listChangeTask setObject:@"stopUpload" forKey:metadata.fileID];
                    NSArray *object = [[NSArray alloc] initWithObjects:session, metadata, findTask, nil];
                    [[NSNotificationCenter defaultCenter] postNotificationName:k_networkingSessionNotification object:object];
                });
            }
        }];
    }
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Shared =====
#pragma --------------------------------------------------------------------------------------------

- (void)readSharedSuccess:(CCMetadataNet *)metadataNet items:(NSDictionary *)items openWindow:(BOOL)openWindow
{
    [_hud hideHud];
    
    AppDelegate *appDelegate = (AppDelegate *)[[UIApplication sharedApplication] delegate];
    
    // change account ?
    //TableAccount *record = [CCCoreData getActiveAccount];
    tableAccount *record = [[NCManageDatabase sharedInstance] getAccountActive];
    if([record.account isEqualToString:metadataNet.account] == NO)
        return;
    
    NSArray *result = [[NCManageDatabase sharedInstance] updateShare:items account:appDelegate.activeAccount activeUrl:appDelegate.activeUrl];
    appDelegate.sharesLink = result[0];
    appDelegate.sharesUserAndGroup = result[1];
    
    if (openWindow) {
            
        if (_shareOC) {
                
            [_shareOC reloadData];
                
        } else {
            
            CCMetadata *metadata = [CCCoreData getMetadataWithPreficate:[NSPredicate predicateWithFormat:@"(fileID == %@) AND (account == %@)", metadataNet.fileID, app.activeAccount] context:nil];
            
            // Apriamo la view
            _shareOC = [[UIStoryboard storyboardWithName:@"CCShare" bundle:nil] instantiateViewControllerWithIdentifier:@"CCShareOC"];
            
            _shareOC.delegate = self;
            _shareOC.metadata = metadata;
            _shareOC.serverUrl = metadataNet.serverUrl;
            
            _shareOC.shareLink = [app.sharesLink objectForKey:metadata.fileID];
            _shareOC.shareUserAndGroup = [app.sharesUserAndGroup objectForKey:metadata.fileID];
            
            [_shareOC setModalPresentationStyle:UIModalPresentationFormSheet];
            [self presentViewController:_shareOC animated:YES completion:nil];
        }
    }

    [self tableViewReload];
}

- (void)shareFailure:(CCMetadataNet *)metadataNet message:(NSString *)message errorCode:(NSInteger)errorCode
{
    [_hud hideHud];
    
    [app messageNotification:@"_share_" description:message visible:YES delay:k_dismissAfterSecond type:TWMessageBarMessageTypeError errorCode:errorCode];

    if (_shareOC)
        [_shareOC reloadData];
    
    [self tableViewReload];
    
    if (errorCode == 401)
        [self changePasswordAccount];
}

- (void)share:(CCMetadata *)metadata serverUrl:(NSString *)serverUrl password:(NSString *)password
{
    CCMetadataNet *metadataNet = [[CCMetadataNet alloc] initWithAccount:app.activeAccount];
    
    metadataNet.action = actionShare;
    metadataNet.fileID = metadata.fileID;
    metadataNet.fileName = [CCUtility returnFileNamePathFromFileName:metadata.fileName serverUrl:serverUrl activeUrl:app.activeUrl];
    metadataNet.fileNamePrint = metadata.fileNamePrint;
    metadataNet.password = password;
    metadataNet.selector = selectorShare;
    metadataNet.serverUrl = serverUrl;
        
    [app addNetworkingOperationQueue:app.netQueue delegate:self metadataNet:metadataNet];

    [_hud visibleHudTitle:NSLocalizedString(@"_creating_sharing_", nil) mode:MBProgressHUDModeIndeterminate color:nil];
}

- (void)unShareSuccess:(CCMetadataNet *)metadataNet
{
    [_hud hideHud];
    
    AppDelegate *appDelegate = (AppDelegate *)[[UIApplication sharedApplication] delegate];

    // rimuoviamo la condivisione da db
    NSArray *result = [[NCManageDatabase sharedInstance] unShare:metadataNet.share fileName:metadataNet.fileName serverUrl:metadataNet.serverUrl sharesLink:appDelegate.sharesLink sharesUserAndGroup:appDelegate.sharesUserAndGroup account:appDelegate.activeAccount];
    
    appDelegate.sharesLink = result[0];
    appDelegate.sharesUserAndGroup = result[1];
    
    if (_shareOC)
        [_shareOC reloadData];
    
    [self tableViewReload];
}

- (void)unShare:(NSString *)share metadata:(CCMetadata *)metadata serverUrl:(NSString *)serverUrl
{
    CCMetadataNet *metadataNet = [[CCMetadataNet alloc] initWithAccount:app.activeAccount];
    
    metadataNet.action = actionUnShare;
    metadataNet.fileID = metadata.fileID;
    metadataNet.fileName = metadata.fileName;
    metadataNet.fileNamePrint = metadata.fileNamePrint;
    metadataNet.selector = selectorUnshare;
    metadataNet.serverUrl = serverUrl;
    metadataNet.share = share;
   
    [app addNetworkingOperationQueue:app.netQueue delegate:self metadataNet:metadataNet];
    
    [_hud visibleHudTitle:NSLocalizedString(@"_updating_sharing_", nil) mode:MBProgressHUDModeIndeterminate color:nil];
}

- (void)updateShare:(NSString *)share metadata:(CCMetadata *)metadata serverUrl:(NSString *)serverUrl password:(NSString *)password expirationTime:(NSString *)expirationTime permission:(NSInteger)permission
{
    CCMetadataNet *metadataNet = [[CCMetadataNet alloc] initWithAccount:app.activeAccount];
    
    metadataNet.action = actionUpdateShare;
    metadataNet.fileID = metadata.fileID;
    metadataNet.expirationTime = expirationTime;
    metadataNet.password = password;
    metadataNet.selector = selectorUpdateShare;
    metadataNet.serverUrl = serverUrl;
    metadataNet.share = share;
    metadataNet.sharePermission = permission;
        
    [app addNetworkingOperationQueue:app.netQueue delegate:self metadataNet:metadataNet];

    [_hud visibleHudTitle:NSLocalizedString(@"_updating_sharing_", nil) mode:MBProgressHUDModeIndeterminate color:nil];
}

- (void)getUserAndGroupSuccess:(CCMetadataNet *)metadataNet items:(NSArray *)items
{
    [_hud hideHud];
    
    if (_shareOC)
        [_shareOC reloadUserAndGroup:items];
}

- (void)getUserAndGroupFailure:(CCMetadataNet *)metadataNet message:(NSString *)message errorCode:(NSInteger)errorCode
{
    [_hud hideHud];
    
    [app messageNotification:@"_error_" description:message visible:YES delay:k_dismissAfterSecond type:TWMessageBarMessageTypeError errorCode:errorCode];
}

- (void)getUserAndGroup:(NSString *)find
{
    CCMetadataNet *metadataNet = [[CCMetadataNet alloc] initWithAccount:app.activeAccount];
    
    metadataNet.action = actionGetUserAndGroup;
    metadataNet.options = find;
    metadataNet.selector = selectorGetUserAndGroup;
        
    [app addNetworkingOperationQueue:app.netQueue delegate:self metadataNet:metadataNet];
    
    [_hud visibleIndeterminateHud];
}

- (void)shareUserAndGroup:(NSString *)user shareeType:(NSInteger)shareeType permission:(NSInteger)permission metadata:(CCMetadata *)metadata directoryID:(NSString *)directoryID serverUrl:(NSString *)serverUrl
{
    CCMetadataNet *metadataNet = [[CCMetadataNet alloc] initWithAccount:app.activeAccount];

    metadataNet.action = actionShareWith;
    metadataNet.fileID = metadata.fileID;
    metadataNet.directoryID = directoryID;
    metadataNet.fileName = [CCUtility returnFileNamePathFromFileName:metadata.fileName serverUrl:serverUrl activeUrl:app.activeUrl];
    metadataNet.fileNamePrint = metadata.fileNamePrint;
    metadataNet.serverUrl = serverUrl;
    metadataNet.selector = selectorShare;
    metadataNet.share = user;
    metadataNet.shareeType = shareeType;
    metadataNet.sharePermission = permission;

    [app addNetworkingOperationQueue:app.netQueue delegate:self metadataNet:metadataNet];
    
    [_hud visibleHudTitle:NSLocalizedString(@"_creating_sharing_", nil) mode:MBProgressHUDModeIndeterminate color:nil];
}

- (void)openWindowShare:(CCMetadata *)metadata
{
    CCMetadataNet *metadataNet = [[CCMetadataNet alloc] initWithAccount:app.activeAccount];
    
    metadataNet.action = actionReadShareServer;
    metadataNet.fileID = metadata.fileID;
    metadataNet.fileName = metadata.fileName;
    metadataNet.fileNamePrint = metadata.fileNamePrint;
    metadataNet.selector = selectorOpenWindowShare;
    metadataNet.serverUrl = [CCCoreData getServerUrlFromDirectoryID:metadata.directoryID activeAccount:metadata.account];
    
    [app addNetworkingOperationQueue:app.netQueue delegate:self metadataNet:metadataNet];
    
    [_hud visibleIndeterminateHud];
}

- (void)tapActionShared:(UITapGestureRecognizer *)tapGesture
{
    CGPoint location = [tapGesture locationInView:self.tableView];
    NSIndexPath * indexPath = [self.tableView indexPathForRowAtPoint:location];
    
    CCMetadata *metadata = [self getMetadataFromSectionDataSource:indexPath];
    
    if (metadata)
        [self openWindowShare:metadata];
}

- (void)tapActionConnectionMounted:(UITapGestureRecognizer *)tapGesture
{
    CGPoint location = [tapGesture locationInView:self.tableView];
    NSIndexPath * indexPath = [self.tableView indexPathForRowAtPoint:location];
    
    CCMetadata *metadata = [self getMetadataFromSectionDataSource:indexPath];
    
    if (metadata) {
        
        CCShareInfoCMOC *vc = [[UIStoryboard storyboardWithName:@"CCShare" bundle:nil] instantiateViewControllerWithIdentifier:@"CCShareInfoCMOC"];
        
        vc.metadata = metadata;
        
        [vc setModalPresentationStyle:UIModalPresentationFormSheet];
        [self presentViewController:vc animated:YES completion:nil];
    }
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Favorite =====
#pragma --------------------------------------------------------------------------------------------

- (void)settingFavoriteSuccess:(CCMetadataNet *)metadataNet
{
    [CCCoreData setMetadataFavoriteFileID:metadataNet.fileID favorite:[metadataNet.options boolValue] activeAccount:app.activeAccount context:nil];
    _dateReadDataSource = nil;
    
    if (_isSearchMode)
        [self readFolderWithForced:YES serverUrl:metadataNet.serverUrl];
    else
        [self reloadDatasource:metadataNet.serverUrl fileID:metadataNet.fileID selector:metadataNet.selector];
    
    CCMetadata *metadata = [CCCoreData getMetadataWithPreficate:[NSPredicate predicateWithFormat:@"(fileID == %@) AND (account == %@)", metadataNet.fileID, app.activeAccount] context:nil];
    
    if (metadata.directory && metadata.favorite) {
        
        NSString *dir = [CCUtility stringAppendServerUrl:metadataNet.serverUrl addFileName:metadata.fileNameData];
        
        [[CCSynchronize sharedSynchronize] addFavoriteFolder:dir];
    }
}

- (void)settingFavoriteFailure:(CCMetadataNet *)metadataNet message:(NSString *)message errorCode:(NSInteger)errorCode
{
}

- (void)addFavorite:(CCMetadata *)metadata
{
    if (metadata.directory) {
        
        [[CCActions sharedInstance] settingFavorite:metadata favorite:YES delegate:self];
        
    } else {
    
        NSString *serverUrl = [CCCoreData getServerUrlFromDirectoryID:metadata.directoryID activeAccount:metadata.account];
    
        [[CCNetworking sharedNetworking] downloadFile:metadata serverUrl:serverUrl downloadData:YES downloadPlist:NO selector:selectorAddFavorite selectorPost:nil session:k_download_session taskStatus:k_taskStatusResume delegate:self];
    }
}

- (void)removeFavorite:(CCMetadata *)metadata
{
    [[CCActions sharedInstance] settingFavorite:metadata favorite:NO delegate:self];
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Offline =====
#pragma --------------------------------------------------------------------------------------------

- (void)addOffline:(CCMetadata *)metadata
{
    NSString *serverUrl = [CCCoreData getServerUrlFromDirectoryID:metadata.directoryID activeAccount:metadata.account];
    
    [[CCNetworking sharedNetworking] downloadFile:metadata serverUrl:serverUrl downloadData:YES downloadPlist:NO selector:selectorAddOffline selectorPost:nil session:k_download_session taskStatus:k_taskStatusResume delegate:self];
    
    NSIndexPath *indexPath = [_sectionDataSource.fileIDIndexPath objectForKey:metadata.fileID];
    if (indexPath) [self.tableView reloadRowsAtIndexPaths:[NSArray arrayWithObjects:indexPath, nil] withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)removeOffline:(CCMetadata *)metadata
{
    [CCCoreData setOfflineLocalFileID:metadata.fileID offline:NO activeAccount:app.activeAccount];
    
    NSIndexPath *indexPath = [_sectionDataSource.fileIDIndexPath objectForKey:metadata.fileID];
    if (indexPath) [self.tableView reloadRowsAtIndexPaths:[NSArray arrayWithObjects:indexPath, nil] withRowAnimation:UITableViewRowAnimationAutomatic];
}


#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Local =====
#pragma --------------------------------------------------------------------------------------------

- (void)addLocal:(CCMetadata *)metadata
{
    if (metadata.errorPasscode || !metadata.uuid) return;
    
    NSString *serverUrl = [CCCoreData getServerUrlFromDirectoryID:metadata.directoryID activeAccount:metadata.account];

    if ([metadata.type isEqualToString: k_metadataType_file])
        [[CCNetworking sharedNetworking] downloadFile:metadata serverUrl:serverUrl downloadData:YES downloadPlist:NO selector:selectorAddLocal selectorPost:nil session:k_download_session taskStatus:k_taskStatusResume delegate:self];
    
    if ([metadata.type isEqualToString: k_metadataType_template]) {
        
        [CCUtility copyFileAtPath:[NSString stringWithFormat:@"%@/%@", app.directoryUser, metadata.fileName] toPath:[NSString stringWithFormat:@"%@/%@", [CCUtility getDirectoryLocal], metadata.fileName]];
        
        [app messageNotification:@"_add_local_" description:@"_file_saved_local_" visible:YES delay:k_dismissAfterSecond type:TWMessageBarMessageTypeSuccess errorCode:0];
    }
    
    NSIndexPath *indexPath = [_sectionDataSource.fileIDIndexPath objectForKey:metadata.fileID];
    if (indexPath) [self.tableView reloadRowsAtIndexPaths:[NSArray arrayWithObjects:indexPath, nil] withRowAnimation:UITableViewRowAnimationAutomatic];
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Open in... =====
#pragma --------------------------------------------------------------------------------------------

- (void)openIn:(CCMetadata *)metadata
{
    NSString *serverUrl = [CCCoreData getServerUrlFromDirectoryID:metadata.directoryID activeAccount:metadata.account];

    [[CCNetworking sharedNetworking] downloadFile:metadata serverUrl:serverUrl downloadData:YES downloadPlist:NO selector:selectorOpenIn selectorPost:nil session:k_download_session taskStatus:k_taskStatusResume delegate:self];
    
    NSIndexPath *indexPath = [_sectionDataSource.fileIDIndexPath objectForKey:metadata.fileID];
    if (indexPath) [self.tableView reloadRowsAtIndexPaths:[NSArray arrayWithObjects:indexPath, nil] withRowAnimation:UITableViewRowAnimationAutomatic];
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Remove Local File =====
#pragma --------------------------------------------------------------------------------------------

- (void)removeLocalFile:(CCMetadata *)metadata
{
    NSString *serverUrl = [CCCoreData getServerUrlFromDirectoryID:_metadata.directoryID activeAccount:_metadata.account];

    [CCCoreData deleteLocalFileWithPredicate:[NSPredicate predicateWithFormat:@"(account == %@) AND (fileID == %@)", app.activeAccount, metadata.fileID]];
    
    [[NSFileManager defaultManager] removeItemAtPath:[NSString stringWithFormat:@"%@/%@", app.directoryUser, metadata.fileID] error:nil];
    
    [self reloadDatasource:serverUrl fileID:metadata.fileID selector:nil];
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Order Table & GroupBy & DirectoryOnTop =====
#pragma --------------------------------------------------------------------------------------------

- (void)orderTable:(NSString *)order
{
    [CCUtility setOrderSettings:order];
    
    // Clear data-read of DataSource
    [[NSNotificationCenter defaultCenter] postNotificationName:@"clearDateReadDataSource" object:nil];
}

- (void)ascendingTable:(BOOL)ascending
{
    [CCUtility setAscendingSettings:ascending];
    
    // Clear data-read of DataSource
    [[NSNotificationCenter defaultCenter] postNotificationName:@"clearDateReadDataSource" object:nil];
}

- (void)directoryOnTop:(BOOL)directoryOnTop
{
    [CCUtility setDirectoryOnTop:directoryOnTop];
    
    // Clear data-read of DataSource
    [[NSNotificationCenter defaultCenter] postNotificationName:@"clearDateReadDataSource" object:nil];
}

- (void)tableGroupBy:(NSString *)groupBy
{
    [CCUtility setGroupBySettings:groupBy];
    
    // Clear data-read of DataSource
    [[NSNotificationCenter defaultCenter] postNotificationName:@"clearDateReadDataSource" object:nil];
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ==== Menu LOGO ====
#pragma --------------------------------------------------------------------------------------------

- (void)menuLogo
{
    // Test crash
    //[[Crashlytics sharedInstance] crash];
    
    if (app.reSelectMenu.isOpen || app.reMainMenu.isOpen)
        return;
    
    // Brand
    if ([NCBrandOptions sharedInstance].disable_multiaccount)
        return;
    
    if ([app.netQueue operationCount] > 0 || [app.netQueueDownload operationCount] > 0 || [app.netQueueDownloadWWan operationCount] > 0 || [app.netQueueUpload operationCount] > 0 || [app.netQueueUploadWWan operationCount] > 0 || [[NCManageDatabase sharedInstance] countAutomaticUploadForAccount:app.activeAccount session:nil] > 0) {
        
        [app messageNotification:@"_transfers_in_queue_" description:nil visible:YES delay:k_dismissAfterSecond type:TWMessageBarMessageTypeInfo errorCode:0];
        return;
    }
    
    //NSArray *listTableAccount = [CCCoreData getAllTableAccount];
    NSArray *listTableAccount = [[NCManageDatabase sharedInstance] getAccounts:nil];
    
    NSMutableArray *menuArray = [NSMutableArray new];
    
    for (TableAccount *record in listTableAccount) {
     
        if ([record.account isEqualToString:app.activeAccount]) continue;
        
        CCMenuItem *item = [[CCMenuItem alloc] init];
        
        item.title = [record.account stringByTruncatingToWidth:self.view.bounds.size.width - 100 withFont:[UIFont systemFontOfSize:12.0] atEnd:YES];
        item.argument = record.account;
        item.image = [UIImage imageNamed:@"menuLogoUser"];
        item.target = self;
        item.action = @selector(changeDefaultAccount:);
        
        [menuArray addObject:item];
    }
    
    if ([menuArray count] == 0)
        return;
    
    OptionalConfiguration options;
    Color textColor, backgroundColor;
    
    textColor.R = 0;
    textColor.G = 0;
    textColor.B = 0;
    
    backgroundColor.R = 1;
    backgroundColor.G = 1;
    backgroundColor.B = 1;
    
    NSInteger originY = 60;

    options.arrowSize = 9;
    options.marginXSpacing = 7;
    options.marginYSpacing = 10;
    options.intervalSpacing = 20;
    options.menuCornerRadius = 6.5;
    options.maskToBackground = NO;
    options.shadowOfMenu = YES;
    options.hasSeperatorLine = YES;
    options.seperatorLineHasInsets = YES;
    options.textColor = textColor;
    options.menuBackgroundColor = backgroundColor;
    
    CGRect rect = self.view.frame;
    rect.origin.y = rect.origin.y + originY;
    rect.size.height = rect.size.height - originY;
    
    [CCMenuAccount setTitleFont:[UIFont systemFontOfSize:12.0]];
    [CCMenuAccount showMenuInView:self.navigationController.view fromRect:rect menuItems:menuArray withOptions:options];    
}

- (void)changeDefaultAccount:(CCMenuItem *)sender
{
    [_ImageTitleHomeCryptoCloud setUserInteractionEnabled:NO];
    
    // STOP, erase all in  queue networking
    [app cancelAllOperations];
    [[CCNetworking sharedNetworking] settingSessionsDownload:YES upload:YES taskStatus:k_taskStatusCancel activeAccount:app.activeAccount activeUser:app.activeUser activeUrl:app.activeUrl];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
    
        //TableAccount *tableAccount = [CCCoreData setActiveAccount:[sender argument]];
        
        tableAccount *tableAccount = [[NCManageDatabase sharedInstance] setAccountActive:[sender argument]];
        if (tableAccount)
            [app settingActiveAccount:tableAccount.account activeUrl:tableAccount.url activeUser:tableAccount.user activePassword:tableAccount.password];
    
        // go to home sweet home
        [[NSNotificationCenter defaultCenter] postNotificationName:@"initializeMain" object:nil];
        
        [_ImageTitleHomeCryptoCloud setUserInteractionEnabled:YES];
    });
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ==== ReMenu ====
#pragma --------------------------------------------------------------------------------------------

- (void)createReMenuBackgroundView:(REMenu *)menu
{
    __block CGFloat navigationBarH = self.navigationController.navigationBar.frame.size.height + [UIApplication sharedApplication].statusBarFrame.size.height;

    _reMenuBackgroundView.frame = CGRectMake(0, navigationBarH, self.view.frame.size.width, self.view.frame.size.height);
        
    [UIView animateWithDuration:0.2 animations:^{
                
        float height = (self.view.frame.size.height + navigationBarH) - (menu.menuView.frame.size.height - self.navigationController.navigationBar.frame.size.height + 3);
        
        if (height < self.tabBarController.tabBar.frame.size.height)
            height = self.tabBarController.tabBar.frame.size.height;
        
        _reMenuBackgroundView.frame = CGRectMake(0, self.view.frame.size.height + navigationBarH, self.view.frame.size.width, - height);
        
        [self.tabBarController.view addSubview:_reMenuBackgroundView];
    }];
}

- (void)createReMainMenu
{
    NSString *ordinamento;
    NSString *groupBy = _directoryGroupBy;
    __block NSString *nuovoOrdinamento;
    NSString *titoloNuovo, *titoloAttuale;
    BOOL ascendente;
    __block BOOL nuovoAscendente;
    UIImage *image;
    
    // ITEM SELECT ----------------------------------------------------------------------------------------------------
    
    app.selezionaItem = [[REMenuItem alloc] initWithTitle:NSLocalizedString(@"_select_", nil)subtitle:@"" image:[CCGraphics changeThemingColorImage:[UIImage imageNamed:@"seleziona"] color:[NCBrandColor sharedInstance].brand] highlightedImage:nil action:^(REMenuItem *item) {
            if ([_sectionDataSource.allRecordsDataSource count] > 0) {
                [self tableViewSelect:YES];
            }
    }];

    // ITEM ORDER ----------------------------------------------------------------------------------------------------
    
    ordinamento = _directoryOrder;
    if ([ordinamento isEqualToString:@"fileName"]) {
        
        image = [CCGraphics changeThemingColorImage:[UIImage imageNamed:@"MenuOrdeyByDate"] color:[NCBrandColor sharedInstance].brand];
        titoloNuovo = NSLocalizedString(@"_order_by_date_", nil);
        titoloAttuale = NSLocalizedString(@"_current_order_name_", nil);
        nuovoOrdinamento = @"fileDate";
    }
    
    if ([ordinamento isEqualToString:@"fileDate"]) {
        
        image = [CCGraphics changeThemingColorImage:[UIImage imageNamed:@"MenuOrderByFileName"] color:[NCBrandColor sharedInstance].brand];
        titoloNuovo = NSLocalizedString(@"_order_by_name_", nil);
        titoloAttuale = NSLocalizedString(@"_current_order_date_", nil);
        nuovoOrdinamento = @"fileName";
    }
    
    app.ordinaItem = [[REMenuItem alloc] initWithTitle:titoloNuovo subtitle:titoloAttuale image:image highlightedImage:nil action:^(REMenuItem *item) {
        [self orderTable:nuovoOrdinamento];
    }];
    
    // ITEM ASCENDING -----------------------------------------------------------------------------------------------------
    
    ascendente = [CCUtility getAscendingSettings];
    
    if (ascendente)  {
        
        image = [CCGraphics changeThemingColorImage:[UIImage imageNamed:@"MenuOrdinamentoDiscendente"] color:[NCBrandColor sharedInstance].brand];
        titoloNuovo = NSLocalizedString(@"_sort_descending_", nil);
        titoloAttuale = NSLocalizedString(@"_current_sort_ascending_", nil);
        nuovoAscendente = false;
    }
    
    if (!ascendente) {
        
        image = [CCGraphics changeThemingColorImage:[UIImage imageNamed:@"MenuOrdinamentoAscendente"] color:[NCBrandColor sharedInstance].brand];
        titoloNuovo = NSLocalizedString(@"_sort_ascending_", nil);
        titoloAttuale = NSLocalizedString(@"_current_sort_descending_", nil);
        nuovoAscendente = true;
    }
    
    app.ascendenteItem = [[REMenuItem alloc] initWithTitle:titoloNuovo subtitle:titoloAttuale image:image highlightedImage:nil action:^(REMenuItem *item) {
        [self ascendingTable:nuovoAscendente];
    }];
    
    
    // ITEM ALPHABETIC -----------------------------------------------------------------------------------------------------
    
    if ([groupBy isEqualToString:@"alphabetic"])  { titoloNuovo = NSLocalizedString(@"_group_alphabetic_yes_", nil); }
    else { titoloNuovo = NSLocalizedString(@"_group_alphabetic_no_", nil); }
    
    app.alphabeticItem = [[REMenuItem alloc] initWithTitle:titoloNuovo subtitle:@"" image:[CCGraphics changeThemingColorImage:[UIImage imageNamed:@"MenuGroupByAlphabetic"] color:[NCBrandColor sharedInstance].brand] highlightedImage:nil action:^(REMenuItem *item) {
            if ([groupBy isEqualToString:@"alphabetic"]) [self tableGroupBy:@"none"];
            else [self tableGroupBy:@"alphabetic"];
    }];
    
    // ITEM TYPEFILE -------------------------------------------------------------------------------------------------------
    
    if ([groupBy isEqualToString:@"typefile"])  { titoloNuovo = NSLocalizedString(@"_group_typefile_yes_", nil); }
    else { titoloNuovo = NSLocalizedString(@"_group_typefile_no_", nil); }
    
    app.typefileItem = [[REMenuItem alloc] initWithTitle:titoloNuovo subtitle:@"" image:[CCGraphics changeThemingColorImage:[UIImage imageNamed:@"MenuGroupByTypeFile"] color:[NCBrandColor sharedInstance].brand] highlightedImage:nil action:^(REMenuItem *item) {
            if ([groupBy isEqualToString:@"typefile"]) [self tableGroupBy:@"none"];
            else [self tableGroupBy:@"typefile"];
    }];
   

    // ITEM DATE -------------------------------------------------------------------------------------------------------
    
    if ([groupBy isEqualToString:@"date"])  { titoloNuovo = NSLocalizedString(@"_group_date_yes_", nil); }
    else { titoloNuovo = NSLocalizedString(@"_group_date_no_", nil); }
    
    app.dateItem = [[REMenuItem alloc] initWithTitle:titoloNuovo   subtitle:@"" image:[CCGraphics changeThemingColorImage:[UIImage imageNamed:@"MenuGroupByDate"] color:[NCBrandColor sharedInstance].brand] highlightedImage:nil action:^(REMenuItem *item) {
            if ([groupBy isEqualToString:@"date"]) [self tableGroupBy:@"none"];
            else [self tableGroupBy:@"date"];
    }];
    
    // ITEM DIRECTORY ON TOP ------------------------------------------------------------------------------------------------
    
    if ([CCUtility getDirectoryOnTop])  { titoloNuovo = NSLocalizedString(@"_directory_on_top_yes_", nil); }
    else { titoloNuovo = NSLocalizedString(@"_directory_on_top_no_", nil); }
    
    app.directoryOnTopItem = [[REMenuItem alloc] initWithTitle:titoloNuovo subtitle:@"" image:[CCGraphics changeThemingColorImage:[UIImage imageNamed:@"menuDirectoryOnTop"] color:[NCBrandColor sharedInstance].brand] highlightedImage:nil action:^(REMenuItem *item) {
            if ([CCUtility getDirectoryOnTop]) [self directoryOnTop:NO];
            else [self directoryOnTop:YES];
    }];
    

    // REMENU --------------------------------------------------------------------------------------------------------------

    app.reMainMenu = [[REMenu alloc] initWithItems:@[app.selezionaItem, app.ordinaItem, app.ascendenteItem, app.alphabeticItem, app.typefileItem, app.dateItem, app.directoryOnTopItem]];
    
    app.reMainMenu.imageOffset = CGSizeMake(5, -1);
    
    app.reMainMenu.separatorOffset = CGSizeMake(50.0, 0.0);
    app.reMainMenu.imageOffset = CGSizeMake(0, 0);
    app.reMainMenu.waitUntilAnimationIsComplete = NO;
    
    app.reMainMenu.separatorHeight = 0.5;
    app.reMainMenu.separatorColor = [NCBrandColor sharedInstance].seperator;
    
    app.reMainMenu.backgroundColor = [NCBrandColor sharedInstance].menuBackground;
    app.reMainMenu.textColor = [UIColor blackColor];
    app.reMainMenu.textAlignment = NSTextAlignmentLeft;
    app.reMainMenu.textShadowColor = nil;
    app.reMainMenu.textOffset = CGSizeMake(50, 0.0);
    app.reMainMenu.font = [UIFont systemFontOfSize:14.0];
    
    app.reMainMenu.highlightedBackgroundColor = [[NCBrandColor sharedInstance] getColorSelectBackgrond];
    app.reMainMenu.highlightedSeparatorColor = nil;
    app.reMainMenu.highlightedTextColor = [UIColor blackColor];
    app.reMainMenu.highlightedTextShadowColor = nil;
    app.reMainMenu.highlightedTextShadowOffset = CGSizeMake(0, 0);
    
    app.reMainMenu.subtitleTextColor = [UIColor colorWithWhite:0.425 alpha:1];
    app.reMainMenu.subtitleTextAlignment = NSTextAlignmentLeft;
    app.reMainMenu.subtitleTextShadowColor = nil;
    app.reMainMenu.subtitleTextShadowOffset = CGSizeMake(0, 0.0);
    app.reMainMenu.subtitleTextOffset = CGSizeMake(50, 0.0);
    app.reMainMenu.subtitleFont = [UIFont systemFontOfSize:12.0];
    
    app.reMainMenu.subtitleHighlightedTextColor = [UIColor lightGrayColor];
    app.reMainMenu.subtitleHighlightedTextShadowColor = nil;
    app.reMainMenu.subtitleHighlightedTextShadowOffset = CGSizeMake(0, 0);
    
    app.reMainMenu.borderWidth = 0.3;
    app.reMainMenu.borderColor =  [UIColor lightGrayColor];
    
    app.reMainMenu.animationDuration = 0.2;
    app.reMainMenu.closeAnimationDuration = 0.2;
    
    app.reMainMenu.bounce = NO;
    
    [app.reMainMenu setClosePreparationBlock:^{
        
        // Backgroun reMenu (Gesture)
        [_reMenuBackgroundView removeFromSuperview];
        [_reMenuBackgroundView removeGestureRecognizer:_singleFingerTap];
    }];
}

- (void)toggleReMainMenu
{
    if (app.reMainMenu.isOpen) {
        
        [app.reMainMenu close];
        
    } else {
        
        [self createReMainMenu];
        [app.reMainMenu showFromNavigationController:self.navigationController];
        
        // Backgroun reMenu & (Gesture)
        [self createReMenuBackgroundView:app.reMainMenu];
        _singleFingerTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleReMainMenu)];
        [_reMenuBackgroundView addGestureRecognizer:_singleFingerTap];
    }
}

- (void)createReSelectMenu
{
    // ITEM DELETE ------------------------------------------------------------------------------------------------------
    
    app.deleteItem = [[REMenuItem alloc] initWithTitle:NSLocalizedString(@"_delete_selected_files_", nil) subtitle:@"" image:[CCGraphics changeThemingColorImage:[UIImage imageNamed:@"deleteSelectedFiles"] color:[NCBrandColor sharedInstance].brand] highlightedImage:nil action:^(REMenuItem *item) {
            [self deleteSelectionFile];
    }];
    
    // ITEM MOVE ------------------------------------------------------------------------------------------------------
    
    app.moveItem = [[REMenuItem alloc] initWithTitle:NSLocalizedString(@"_move_selected_files_", nil) subtitle:@"" image:[CCGraphics changeThemingColorImage:[UIImage imageNamed:@"moveSelectedFiles"] color:[NCBrandColor sharedInstance].brand] highlightedImage:nil action:^(REMenuItem *item) {
            [self moveOpenWindow:[self.tableView indexPathsForSelectedRows]];
    }];
    
    if (app.isCryptoCloudMode) {
    
        // ITEM ENCRYPTED ------------------------------------------------------------------------------------------------------
    
        app.encryptItem = [[REMenuItem alloc] initWithTitle:NSLocalizedString(@"_encrypted_selected_files_", nil) subtitle:@"" image:[CCGraphics changeThemingColorImage:[UIImage imageNamed:@"encryptedSelectedFiles"] color:[NCBrandColor sharedInstance].brand] highlightedImage:nil action:^(REMenuItem *item) {
                [self performSelector:@selector(encryptedSelectedFiles) withObject:nil];
        }];
    
        // ITEM DECRYPTED ----------------------------------------------------------------------------------------------------
    
        app.decryptItem = [[REMenuItem alloc] initWithTitle:NSLocalizedString(@"_decrypted_selected_files_", nil) subtitle:@"" image:[CCGraphics changeThemingColorImage:[UIImage imageNamed:@"decryptedSelectedFiles"] color:[NCBrandColor sharedInstance].brand] highlightedImage:nil action:^(REMenuItem *item) {
                [self performSelector:@selector(decryptedSelectedFiles) withObject:nil];
        }];
    }
    
    // ITEM DOWNLOAD ----------------------------------------------------------------------------------------------------
    
    app.downloadItem = [[REMenuItem alloc] initWithTitle:NSLocalizedString(@"_download_selected_files_", nil) subtitle:@"" image:[CCGraphics changeThemingColorImage:[UIImage imageNamed:@"downloadSelectedFiles"] color:[NCBrandColor sharedInstance].brand] highlightedImage:nil action:^(REMenuItem *item) {
            [self downloadSelectedFiles];
    }];
    
    // ITEM SAVE IMAGE & VIDEO -------------------------------------------------------------------------------------------
    
    app.saveItem = [[REMenuItem alloc] initWithTitle:NSLocalizedString(@"_save_selected_files_", nil) subtitle:@"" image:[CCGraphics changeThemingColorImage:[UIImage imageNamed:@"saveSelectedFiles"] color:[NCBrandColor sharedInstance].brand] highlightedImage:nil action:^(REMenuItem *item) {
            [self saveSelectedFiles];
    }];

    // REMENU --------------------------------------------------------------------------------------------------------------
    
    if (app.isCryptoCloudMode) {
        app.reSelectMenu = [[REMenu alloc] initWithItems:@[app.deleteItem,app.moveItem, app.encryptItem, app.decryptItem, app.downloadItem, app.saveItem]];
    } else {
        app.reSelectMenu = [[REMenu alloc] initWithItems:@[app.deleteItem,app.moveItem, app.downloadItem, app.saveItem]];
    }
    
    app.reSelectMenu.imageOffset = CGSizeMake(5, -1);
    
    app.reSelectMenu.separatorOffset = CGSizeMake(50.0, 0.0);
    app.reSelectMenu.imageOffset = CGSizeMake(0, 0);
    app.reSelectMenu.waitUntilAnimationIsComplete = NO;
    
    app.reSelectMenu.separatorHeight = 0.5;
    app.reSelectMenu.separatorColor = [NCBrandColor sharedInstance].seperator;
    
    app.reSelectMenu.backgroundColor = [NCBrandColor sharedInstance].menuBackground;
    app.reSelectMenu.textColor = [UIColor blackColor];
    app.reSelectMenu.textAlignment = NSTextAlignmentLeft;
    app.reSelectMenu.textShadowColor = nil;
    app.reSelectMenu.textOffset = CGSizeMake(50, 0.0);
    app.reSelectMenu.font = [UIFont systemFontOfSize:14.0];
    
    app.reSelectMenu.highlightedBackgroundColor = [[NCBrandColor sharedInstance] getColorSelectBackgrond];
    app.reSelectMenu.highlightedSeparatorColor = nil;
    app.reSelectMenu.highlightedTextColor = [UIColor blackColor];
    app.reSelectMenu.highlightedTextShadowColor = nil;
    app.reSelectMenu.highlightedTextShadowOffset = CGSizeMake(0, 0);
    
    app.reSelectMenu.subtitleTextColor = [UIColor colorWithWhite:0.425 alpha:1.000];
    app.reSelectMenu.subtitleTextAlignment = NSTextAlignmentLeft;
    app.reSelectMenu.subtitleTextShadowColor = nil;
    app.reSelectMenu.subtitleTextShadowOffset = CGSizeMake(0, 0.0);
    app.reSelectMenu.subtitleTextOffset = CGSizeMake(50, 0.0);
    app.reSelectMenu.subtitleFont = [UIFont systemFontOfSize:12.0];
    
    app.reSelectMenu.subtitleHighlightedTextColor = [UIColor lightGrayColor];
    app.reSelectMenu.subtitleHighlightedTextShadowColor = nil;
    app.reSelectMenu.subtitleHighlightedTextShadowOffset = CGSizeMake(0, 0);
    
    app.reSelectMenu.borderWidth = 0.3;
    app.reSelectMenu.borderColor =  [UIColor lightGrayColor];
    
    app.reSelectMenu.closeAnimationDuration = 0.2;
    app.reSelectMenu.animationDuration = 0.2;

    app.reSelectMenu.bounce = NO;
    
    [app.reSelectMenu setClosePreparationBlock:^{
        
        // Backgroun reMenu (Gesture)
        [_reMenuBackgroundView removeFromSuperview];
        [_reMenuBackgroundView removeGestureRecognizer:_singleFingerTap];
    }];
}

- (void)toggleReSelectMenu
{
    if (app.reSelectMenu.isOpen) {
        
        [app.reSelectMenu close];
        
    } else {
        
        [self createReSelectMenu];
        [app.reSelectMenu showFromNavigationController:self.navigationController];
        
        // Backgroun reMenu & (Gesture)
        [self createReMenuBackgroundView:app.reSelectMenu];
        _singleFingerTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleReSelectMenu)];
        [_reMenuBackgroundView addGestureRecognizer:_singleFingerTap];
    }
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Long Press Recognized Table View / Menu Controller =====
#pragma --------------------------------------------------------------------------------------------

- (void)onLongPressTableView:(UILongPressGestureRecognizer*)recognizer
{
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        
        UITableView *tableView = (UITableView*)self.view;
        CGPoint touchPoint = [recognizer locationInView:self.view];
        NSIndexPath *indexPath = [tableView indexPathForRowAtPoint:touchPoint];
        
        if (indexPath)
            _metadata = [self getMetadataFromSectionDataSource:indexPath];
        else
            _metadata = nil;
        
        [self becomeFirstResponder];
        
        UIMenuController *menuController = [UIMenuController sharedMenuController];
        
        UIMenuItem *copyFileItem = [[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"_copy_file_", nil) action:@selector(copyFile:)];
        UIMenuItem *copyFilesItem = [[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"_copy_files_", nil) action:@selector(copyFiles:)];

        UIMenuItem *openinFileItem = [[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"_open_in_", nil) action:@selector(openinFile:)];
        
        UIMenuItem *pasteFileItem = [[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"_paste_file_", nil) action:@selector(pasteFile:)];
        UIMenuItem *pasteFileEncryptedItem = [[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"_paste_file_encrypted_", nil) action:@selector(pasteFileEncrypted:)];
        
        UIMenuItem *pasteFilesItem = [[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"_paste_files_", nil) action:@selector(pasteFiles:)];
        UIMenuItem *pasteFilesEncryptedItem = [[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"_paste_files_encrypted_", nil) action:@selector(pasteFilesEncrypted:)];
        
        if (app.isCryptoCloudMode)
            [menuController setMenuItems:[NSArray arrayWithObjects:copyFileItem, copyFilesItem, openinFileItem, pasteFileItem, pasteFilesItem, pasteFileEncryptedItem, pasteFilesEncryptedItem, nil]];
        else
            [menuController setMenuItems:[NSArray arrayWithObjects:copyFileItem, copyFilesItem, openinFileItem, pasteFileItem, pasteFilesItem, nil]];

        [menuController setTargetRect:CGRectMake(touchPoint.x, touchPoint.y, 0.0f, 0.0f) inView:tableView];
        [menuController setMenuVisible:YES animated:YES];
    }
}

- (BOOL)canBecomeFirstResponder
{
    return YES;
}

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender
{
    // For copy file, copy files, Open in ... :
    //
    // NO Directory
    // NO Error Passcode
    // NO In Session mode (download/upload)
    // NO Template
    
    if (@selector(copyFile:) == action || @selector(openinFile:) == action) {
        
        if (_isSelectedMode == NO && _metadata && !_metadata.directory && !_metadata.errorPasscode && [_metadata.session length] == 0 && ![_metadata.typeFile isEqualToString: k_metadataTypeFile_template])  {
            
            // NO Cryptated with Title lenght = 0
            if (!_metadata.cryptated || (_metadata.cryptated && _metadata.title.length > 0))
                return YES;
        }
        return NO;
    }
    
    if (@selector(copyFiles:) == action) {
        
        if (_isSelectedMode) {
            
            NSArray *selectedMetadatas = [self getMetadatasFromSelectedRows:[self.tableView indexPathsForSelectedRows]];
            
            for (CCMetadata *metadata in selectedMetadatas) {
                
                if (!metadata.directory && !metadata.errorPasscode && metadata.session.length == 0 && ![metadata.typeFile isEqualToString: k_metadataTypeFile_template])  {
                    
                    // NO Cryptated with Title lenght = 0
                    if (!metadata.cryptated || (metadata.cryptated && metadata.title.length > 0))
                        return YES;
                }
            }
        }
        return NO;
    }

    if (@selector(pasteFile:) == action || @selector(pasteFileEncrypted:) == action) {
        
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        NSArray *items = [pasteboard items];
        
        if ([items count] == 1) {
            
            // Value : (NSData) metadata
            
            NSDictionary *dic = [items objectAtIndex:0];
            
            NSData *dataMetadata = [dic objectForKey: k_metadataKeyedUnarchiver];
            CCMetadata *metadata = [NSKeyedUnarchiver unarchiveObjectWithData:dataMetadata];
            
            //TableAccount *account = [CCCoreData getTableAccountFromAccount:metadata.account];
            
            NSArray *accounts = [[NCManageDatabase sharedInstance] getAccounts:metadata.account];
            tableAccount *account = [accounts objectAtIndex:0];
            NSString *directoryUser = [CCUtility getDirectoryActiveUser:account.user activeUrl:account.url];
            
            if (directoryUser) {
                if ([[NSFileManager defaultManager] fileExistsAtPath:[NSString stringWithFormat:@"%@/%@", directoryUser, metadata.fileID]])
                    return YES;
            }
            
            return NO;

        } else return NO;
    }
    
    if (@selector(pasteFiles:) == action || @selector(pasteFilesEncrypted:) == action) {
        
        BOOL isValid = NO;
        
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        NSArray *items = [pasteboard items];
        
        if ([items count] <= 1) return NO;
        
        for (NSDictionary *dic in items) {
            
            // Value : (NSData) metadata
            
            NSData *dataMetadata = [dic objectForKey: k_metadataKeyedUnarchiver];
            CCMetadata *metadata = [NSKeyedUnarchiver unarchiveObjectWithData:dataMetadata];
            
            //TableAccount *account = [CCCoreData getTableAccountFromAccount:metadata.account];
            
            NSArray *accounts = [[NCManageDatabase sharedInstance] getAccounts:metadata.account];
            tableAccount *account = [accounts objectAtIndex:0];
            
            NSString *directoryUser = [CCUtility getDirectoryActiveUser:account.user activeUrl:account.url];
            
            if (directoryUser) {
                if ([[NSFileManager defaultManager] fileExistsAtPath:[NSString stringWithFormat:@"%@/%@", directoryUser, metadata.fileID]])
                    isValid = YES;
            }
        }
        
        return isValid;
    }
    
    return NO;
}

/************************************ COPY ************************************/

- (void)copyFile:(id)sender
{
    // Remove all item
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    pasteboard.items = [[NSArray alloc] init];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:[NSString stringWithFormat:@"%@/%@", app.directoryUser,_metadata.fileID]]) {
        
        [self copyFileToPasteboard:_metadata];
        
    } else {
        
        NSString *serverUrl = [CCCoreData getServerUrlFromDirectoryID:_metadata.directoryID activeAccount:_metadata.account];
        
        [[CCNetworking sharedNetworking] downloadFile:_metadata serverUrl:serverUrl downloadData:YES downloadPlist:NO selector:selectorLoadCopy selectorPost:nil session:k_download_session taskStatus:k_taskStatusResume delegate:self];
    }
}

- (void)copyFiles:(id)sender
{
    // Remove all item
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    pasteboard.items = [[NSArray alloc] init];
    
    NSArray *selectedMetadatas = [self getMetadatasFromSelectedRows:[self.tableView indexPathsForSelectedRows]];
    
    for (CCMetadata *metadata in selectedMetadatas) {
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:[NSString stringWithFormat:@"%@/%@", app.directoryUser, metadata.fileID]]) {
            
            [self copyFileToPasteboard:metadata];
            
        } else {

            NSString *serverUrl = [CCCoreData getServerUrlFromDirectoryID:_metadata.directoryID activeAccount:_metadata.account];

            [[CCNetworking sharedNetworking] downloadFile:metadata serverUrl:serverUrl downloadData:YES downloadPlist:NO selector:selectorLoadCopy selectorPost:nil session:k_download_session taskStatus:k_taskStatusResume delegate:self];
        }
    }
    
    [self tableViewSelect:NO];
}

- (void)copyFileToPasteboard:(CCMetadata *)metadata
{
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    NSMutableArray *items = [[NSMutableArray alloc] initWithArray:pasteboard.items];
    
    // Value : (NSData) metadata
    
    NSDictionary *item = [NSDictionary dictionaryWithObjectsAndKeys:[NSKeyedArchiver archivedDataWithRootObject:metadata], k_metadataKeyedUnarchiver,nil];
    [items addObject:item];
    
    [pasteboard setItems:items];
}

/************************************ OPEN IN ... ************************************/

- (void)openinFile:(id)sender
{
    [self openIn:_metadata];
}

/************************************ PASTE ************************************/

- (void)pasteFile:(id)sender
{
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    [self uploadFilePasteArray:[pasteboard items] cryptated:NO];
}

- (void)pasteFileEncrypted:(id)sender
{
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    [self uploadFilePasteArray:[pasteboard items] cryptated:YES];
}

- (void)pasteFiles:(id)sender
{
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    [self uploadFilePasteArray:[pasteboard items] cryptated:NO];
}

- (void)pasteFilesEncrypted:(id)sender
{
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    [self uploadFilePasteArray:[pasteboard items] cryptated:YES];
}

- (void)uploadFilePasteArray:(NSArray *)items cryptated:(BOOL)cryptated
{
    for (NSDictionary *dic in items) {
        
        // Value : (NSData) metadata
        
        NSData *dataMetadata = [dic objectForKey: k_metadataKeyedUnarchiver];
        CCMetadata *metadata = [NSKeyedUnarchiver unarchiveObjectWithData:dataMetadata];
            
        //TableAccount *account = [CCCoreData getTableAccountFromAccount:metadata.account];
        
        NSArray *accounts = [[NCManageDatabase sharedInstance] getAccounts:metadata.account];
        tableAccount *account = [accounts objectAtIndex:0];
        
        NSString *directoryUser = [CCUtility getDirectoryActiveUser:account.user activeUrl:account.url];
            
        if (directoryUser) {
            
            if ([[NSFileManager defaultManager] fileExistsAtPath:[NSString stringWithFormat:@"%@/%@", directoryUser, metadata.fileID]]) {
                
                [CCUtility copyFileAtPath:[NSString stringWithFormat:@"%@/%@", directoryUser, metadata.fileID] toPath:[NSString stringWithFormat:@"%@/%@", app.directoryUser, metadata.fileNamePrint]];
            
                [[CCNetworking sharedNetworking] uploadFile:metadata.fileNamePrint serverUrl:_serverUrl cryptated:cryptated onlyPlist:NO session:k_upload_session taskStatus:k_taskStatusResume selector:nil selectorPost:nil errorCode:0 delegate:nil];
            }
        }
    }
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Lock Passcode =====
#pragma --------------------------------------------------------------------------------------------

- (NSUInteger)passcodeViewControllerNumberOfFailedAttempts:(CCBKPasscode *)aViewController
{
    return _failedAttempts;
}

- (NSDate *)passcodeViewControllerLockUntilDate:(CCBKPasscode *)aViewController
{
    return _lockUntilDate;
}

- (void)passcodeViewCloseButtonPressed:(id)sender
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)passcodeViewController:(CCBKPasscode *)aViewController authenticatePasscode:(NSString *)aPasscode resultHandler:(void (^)(BOOL))aResultHandler
{
    if (aViewController.fromType == CCBKPasscodeFromLockScreen || aViewController.fromType == CCBKPasscodeFromLockDirectory || aViewController.fromType == CCBKPasscodeFromDisactivateDirectory ) {
        if ([aPasscode isEqualToString:[CCUtility getBlockCode]]) {
            _lockUntilDate = nil;
            _failedAttempts = 0;
            aResultHandler(YES);
        } else aResultHandler(NO);
    } else aResultHandler(YES);
}

- (void)passcodeViewController:(CCBKPasscode *)aViewController didFinishWithPasscode:(NSString *)aPasscode
{
    [aViewController dismissViewControllerAnimated:YES completion:nil];
    
    switch (aViewController.type) {
            
        case BKPasscodeViewControllerCheckPasscodeType: {
            
            if (aViewController.fromType == CCBKPasscodeFromPasscode) {
                
                // verifichiamo se il passcode è corretto per il seguente file -> UUID
                if ([[CCCrypto sharedManager] verifyPasscode:aPasscode uuid:_metadata.uuid text:_metadata.title]) {
                    
                    // scriviamo il passcode
                    [CCUtility setKeyChainPasscodeForUUID:_metadata.uuid conPasscode:aPasscode];
                    
                    [self readFolderWithForced:YES serverUrl:_serverUrl];
                    
                } else {
                    
                    UIAlertView * alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"_error_", nil) message:NSLocalizedString(@"_error_passcode_", nil) delegate:nil cancelButtonTitle:nil otherButtonTitles:NSLocalizedString(@"_ok_", nil), nil];
                    [alertView show];
                }
            }
            
            if (aViewController.fromType == CCBKPasscodeFromLockDirectory) {
                
                // possiamo procedere alla prossima directory
                [self performSegueDirectoryWithControlPasscode:false];
                
                // avviamo la sessione Passcode Lock con now
                app.sessionePasscodeLock = [NSDate date];
            }
            
            // disattivazione lock cartella
            if (aViewController.fromType == CCBKPasscodeFromDisactivateDirectory) {
                
                NSString *serverUrl = [CCCoreData getServerUrlFromDirectoryID:_metadata.directoryID activeAccount:_metadata.account];
                NSString *lockServerUrl = [CCUtility stringAppendServerUrl:serverUrl addFileName:_metadata.fileNameData];
                
                if ([CCCoreData setDirectoryUnLock:lockServerUrl activeAccount:app.activeAccount] == NO) {
                    
                    [app messageNotification:@"_error_" description:@"_error_operation_canc_" visible:YES delay:k_dismissAfterSecond type:TWMessageBarMessageTypeError errorCode:0];
                }
                
                [self.tableView reloadData];
            }
        }
            break;
        default:
            break;
    }
}

- (void)comandoLockPassword
{
    NSString *serverUrl = [CCCoreData getServerUrlFromDirectoryID:_metadata.directoryID activeAccount:_metadata.account];
    NSString *lockServerUrl = [CCUtility stringAppendServerUrl:serverUrl addFileName:_metadata.fileNameData];

    // se non è abilitato il Lock Passcode esci
    if ([[CCUtility getBlockCode] length] == 0) {
        UIAlertView * alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"_warning_", nil) message:NSLocalizedString(@"_only_lock_passcode_", nil) delegate:nil cancelButtonTitle:nil otherButtonTitles:NSLocalizedString(@"_ok_", nil), nil];
        [alertView show];
        return;
    }
    
    // se è richiesta la disattivazione si chiede la password
    if ([CCCoreData isDirectoryLock:lockServerUrl activeAccount:app.activeAccount]) {
        
        CCBKPasscode *viewController = [[CCBKPasscode alloc] initWithNibName:nil bundle:nil];
        viewController.delegate = self;
        viewController.fromType = CCBKPasscodeFromDisactivateDirectory;
        viewController.type = BKPasscodeViewControllerCheckPasscodeType;
        viewController.inputViewTitlePassword = YES;
        
        if ([CCUtility getSimplyBlockCode]) {
            
            viewController.passcodeStyle = BKPasscodeInputViewNumericPasscodeStyle;
            viewController.passcodeInputView.maximumLength = 6;
            
        } else {
            
            viewController.passcodeStyle = BKPasscodeInputViewNormalPasscodeStyle;
            viewController.passcodeInputView.maximumLength = 64;
        }
        
        BKTouchIDManager *touchIDManager = [[BKTouchIDManager alloc] initWithKeychainServiceName:k_serviceShareKeyChain];
        touchIDManager.promptText = NSLocalizedString(@"_scan_fingerprint_", nil);
        viewController.touchIDManager = touchIDManager;

        viewController.title = NSLocalizedString(@"_passcode_protection_", nil);
        viewController.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(passcodeViewCloseButtonPressed:)];
        viewController.navigationItem.leftBarButtonItem.tintColor = [NCBrandColor sharedInstance].cryptocloud;
        
        UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:viewController];
        [self presentViewController:navigationController animated:YES completion:nil];
        
        return;
    }
    
    // ---------------- ACTIVATE PASSWORD
    
    if([CCCoreData setDirectoryLock:lockServerUrl activeAccount:app.activeAccount]) {
        
        NSIndexPath *indexPath = [_sectionDataSource.fileIDIndexPath objectForKey:_metadata.fileID];
        if (indexPath) [self.tableView reloadRowsAtIndexPaths:[NSArray arrayWithObjects:indexPath, nil] withRowAnimation:UITableViewRowAnimationAutomatic];

        
    } else {
        
        [app messageNotification:@"_error_" description:@"_error_operation_canc_" visible:YES delay:k_dismissAfterSecond type:TWMessageBarMessageTypeError errorCode:0];
    }
}

#pragma mark -
#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Swipe Tablet -> menu =====
#pragma --------------------------------------------------------------------------------------------

// more
- (NSString *)tableView:(UITableView *)tableView titleForSwipeAccessoryButtonForRowAtIndexPath:(NSIndexPath *)indexPath {
    return NSLocalizedString(@"_more_", nil);
}

- (void)tableView:(UITableView *)tableView swipeAccessoryButtonPushedForRowAtIndexPath:(NSIndexPath *)indexPath
{
    _metadata = [self getMetadataFromSectionDataSource:indexPath];
    
    NSString *serverUrl = [CCCoreData getServerUrlFromDirectoryID:_metadata.directoryID activeAccount:_metadata.account];
    
    NSString *titoloCriptaDecripta, *titoloOffline, *titoloLock, *titleOfflineFolder, *titleFavorite;
    BOOL offlineFolder = NO;
    
    if (_metadata.cryptated) titoloCriptaDecripta = [NSString stringWithFormat:NSLocalizedString(@"_decrypt_", nil)];
    else titoloCriptaDecripta = [NSString stringWithFormat:NSLocalizedString(@"_encrypt_", nil)];
    
    if ([CCCoreData isOfflineLocalFileID:_metadata.fileID activeAccount:app.activeAccount]) titoloOffline = [NSString stringWithFormat:NSLocalizedString(@"_remove_offline_", nil)];
    else titoloOffline = [NSString stringWithFormat:NSLocalizedString(@"_add_offline_", nil)];
    
    NSString *offlineServerUrl = [CCUtility stringAppendServerUrl:serverUrl addFileName:_metadata.fileNameData];
    if (_metadata.directory && [CCCoreData isOfflineDirectoryServerUrl:offlineServerUrl activeAccount:app.activeAccount]) {
        
        titleOfflineFolder = [NSString stringWithFormat:NSLocalizedString(@"_remove_offline_", nil)];
        offlineFolder = YES;
        
    } else titleOfflineFolder = [NSString stringWithFormat:NSLocalizedString(@"_add_offline_", nil)];
    
    if (_metadata.favorite) {
        
        titleFavorite = [NSString stringWithFormat:NSLocalizedString(@"_remove_favorites_", nil)];
    } else {
        
        titleFavorite = [NSString stringWithFormat:NSLocalizedString(@"_add_favorites_", nil)];
    }
    
    if (_metadata.directory) {
        // calcolo lockServerUrl
        NSString *lockServerUrl = [CCUtility stringAppendServerUrl:serverUrl addFileName:_metadata.fileNameData];
        
        if ([CCCoreData isDirectoryLock:lockServerUrl activeAccount:app.activeAccount]) titoloLock = [NSString stringWithFormat:NSLocalizedString(@"_remove_passcode_", nil)];
        else titoloLock = [NSString stringWithFormat:NSLocalizedString(@"_protect_passcode_", nil)];
    }
    
    TableLocalFile *recordLocalFile = [CCCoreData getLocalFileWithFileID:_metadata.fileID activeAccount:app.activeAccount];

    /******************************************* AHKActionSheet *******************************************/
    
    AHKActionSheet *actionSheet = [[AHKActionSheet alloc] initWithView:self.view title:nil];
    
    actionSheet.animationDuration = 0.2;
    
    actionSheet.blurRadius = 0.0f;
    actionSheet.blurTintColor = [UIColor colorWithWhite:0.0f alpha:0.50f];
    
    actionSheet.buttonHeight = 50.0;
    actionSheet.cancelButtonHeight = 50.0f;
    actionSheet.separatorHeight = 5.0f;
    
    actionSheet.automaticallyTintButtonImages = @(NO);
    
    actionSheet.encryptedButtonTextAttributes = @{ NSFontAttributeName:[UIFont systemFontOfSize:16], NSForegroundColorAttributeName:[NCBrandColor sharedInstance].cryptocloud };
    actionSheet.buttonTextAttributes = @{ NSFontAttributeName:[UIFont systemFontOfSize:16], NSForegroundColorAttributeName:[UIColor blackColor] };
    actionSheet.cancelButtonTextAttributes = @{ NSFontAttributeName:[UIFont systemFontOfSize:16], NSForegroundColorAttributeName:[NCBrandColor sharedInstance].brand };
    actionSheet.disableButtonTextAttributes = @{ NSFontAttributeName:[UIFont systemFontOfSize:16], NSForegroundColorAttributeName:[UIColor blackColor] };
    
    actionSheet.separatorColor =  [NCBrandColor sharedInstance].seperator;
    actionSheet.cancelButtonTitle = NSLocalizedString(@"_cancel_",nil);
    
    /******************************************* DIRECTORY *******************************************/
    
    if (_metadata.directory) {
        
        BOOL lockDirectory = NO;
        NSString *dirServerUrl = [CCUtility stringAppendServerUrl:serverUrl addFileName:_metadata.fileNameData];

        // Directory bloccata ?
        if ([CCCoreData isDirectoryLock:dirServerUrl activeAccount:app.activeAccount] && [[CCUtility getBlockCode] length] && app.sessionePasscodeLock == nil) lockDirectory = YES;
        
        //NSString *cameraUploadFolderName = [CCCoreData getCameraUploadFolderNameActiveAccount:app.activeAccount];
        //NSString *cameraUploadFolderPath = [CCCoreData getCameraUploadFolderPathActiveAccount:app.activeAccount activeUrl:app.activeUrl];
        
        NSString *cameraUploadFolderName = [[NCManageDatabase sharedInstance] getAccountsCameraUploadFolderName:app.activeAccount activeUrl:nil];
        NSString *cameraUploadFolderPath = [[NCManageDatabase sharedInstance] getAccountsCameraUploadFolderPath:app.activeAccount activeUrl:app.activeUrl];
        
        [actionSheet addButtonWithTitle: _metadata.fileNamePrint
                                  image: [CCGraphics changeThemingColorImage:[UIImage imageNamed:_metadata.iconName] color:[NCBrandColor sharedInstance].brand]
                        backgroundColor: [NCBrandColor sharedInstance].tabBar
                                 height: 50.0
                                   type: AHKActionSheetButtonTypeDisabled
                                handler: nil
        ];

        if (!lockDirectory && !_metadata.cryptated) {
            
            [actionSheet addButtonWithTitle:titleFavorite
                                      image:[CCGraphics changeThemingColorImage:[UIImage imageNamed:@"actionSheetFavorite"] color:[NCBrandColor sharedInstance].brand]
                            backgroundColor:[UIColor whiteColor]
                                     height: 50.0
                                       type:AHKActionSheetButtonTypeDefault
                                    handler:^(AHKActionSheet *as) {
                                        
                                        // close swipe
                                        [self setEditing:NO animated:YES];
                                        
                                        if (_metadata.favorite)
                                            [self removeFavorite:_metadata];
                                        else
                                            [self addFavorite:_metadata];
                                    }];
        }

        if (_metadata.cryptated == NO && !lockDirectory) {
            
            [actionSheet addButtonWithTitle:NSLocalizedString(@"_share_", nil)
                                      image:[CCGraphics changeThemingColorImage:[UIImage imageNamed:@"actionSheetShare"] color:[NCBrandColor sharedInstance].brand]
                            backgroundColor:[UIColor whiteColor]
                                     height: 50.0
                                       type:AHKActionSheetButtonTypeDefault
                                    handler:^(AHKActionSheet *as) {
                                        
                                        // close swipe
                                        [self setEditing:NO animated:YES];
                                        
                                        [self openWindowShare:_metadata];
                                    }];
        }

        if (!([_metadata.fileName isEqualToString:cameraUploadFolderName] == YES && [serverUrl isEqualToString:cameraUploadFolderPath] == YES) && !lockDirectory) {
            
            [actionSheet addButtonWithTitle:NSLocalizedString(@"_rename_", nil)
                                      image:[CCGraphics changeThemingColorImage:[UIImage imageNamed:@"actionSheetRename"] color:[NCBrandColor sharedInstance].brand]
                            backgroundColor:[UIColor whiteColor]
                                     height: 50.0
                                       type:AHKActionSheetButtonTypeDefault
                                    handler:^(AHKActionSheet *as) {
                                   
                                        // close swipe
                                        [self setEditing:NO animated:YES];
                                        
                                        //chiediamo il nome del file
                                        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"_rename_",nil) message:nil delegate:self cancelButtonTitle:NSLocalizedString(@"_cancel_",nil) otherButtonTitles:NSLocalizedString(@"_save_", nil), nil];
                                        [alertView setAlertViewStyle:UIAlertViewStylePlainTextInput];
                                        alertView.tag = alertRename;
                                        UITextField *textField = [alertView textFieldAtIndex:0];
                                        textField.text = _metadata.fileNamePrint;
                                        [alertView show];
                                    }];
        }
        
        if (!([_metadata.fileName isEqualToString:cameraUploadFolderName] == YES && [serverUrl isEqualToString:cameraUploadFolderPath] == YES) && !lockDirectory) {
            
            [actionSheet addButtonWithTitle:NSLocalizedString(@"_move_", nil)
                                      image:[CCGraphics changeThemingColorImage:[UIImage imageNamed:@"actionSheetMove"] color:[NCBrandColor sharedInstance].brand]
                            backgroundColor:[UIColor whiteColor]
                                     height: 50.0
                                       type:AHKActionSheetButtonTypeDefault
                                    handler:^(AHKActionSheet *as) {
                                        
                                        // close swipe
                                        [self setEditing:NO animated:YES];
                                        
                                        [self moveOpenWindow:[[NSArray alloc] initWithObjects:indexPath, nil]];
                                    }];
        }
        
        if (!([_metadata.fileName isEqualToString:cameraUploadFolderName] == YES && [serverUrl isEqualToString:cameraUploadFolderPath] == YES) && _metadata.cryptated == NO) {
            
            [actionSheet addButtonWithTitle:NSLocalizedString(@"_folder_automatic_upload_", nil)
                                      image:[CCGraphics changeThemingColorImage:[UIImage imageNamed:@"folderphotocamera"] color:[NCBrandColor sharedInstance].brand]
                            backgroundColor:[UIColor whiteColor]
                                     height: 50.0
                                       type:AHKActionSheetButtonTypeDefault
                                    handler:^(AHKActionSheet *as) {
                                        
                                        // close swipe
                                        [self setEditing:NO animated:YES];
                                        
                                        // Settings new folder Automatatic upload
                                       // NSString *oldPath = [CCCoreData getCameraUploadFolderPathActiveAccount:app.activeAccount activeUrl:app.activeUrl];
                                        NSString *oldPath = [[NCManageDatabase sharedInstance] getAccountsCameraUploadFolderPath:app.activeUrl];

                                        
                                        [CCCoreData setCameraUploadFolderName:_metadata.fileName activeAccount:app.activeAccount];
                                        [CCCoreData setCameraUploadFolderPath:serverUrl activeUrl:app.activeUrl activeAccount:app.activeAccount];
                                        
                                        [CCCoreData clearDateReadAccount:app.activeAccount serverUrl:oldPath directoryID:nil];
                                        
                                        if (app.activeAccount.length > 0 && app.activePhotosCameraUpload)
                                            [app.activePhotosCameraUpload reloadDatasourceForced];
                                        
                                        [self readFolderWithForced:YES serverUrl:serverUrl];
                                        
                                        NSLog(@"[LOG] Update Folder Photo");
                                        //NSString *folderCameraUpload = [CCCoreData getCameraUploadFolderNamePathActiveAccount:app.activeAccount activeUrl:app.activeUrl];
                                        NSString *folderCameraUpload = [[NCManageDatabase sharedInstance] getAccountsCameraUploadFolderName:app.activeUrl];
                                        if ([folderCameraUpload length] > 0)
                                            [[CCSynchronize sharedSynchronize] readFolderServerUrl:folderCameraUpload directoryID:[CCCoreData getDirectoryIDFromServerUrl:folderCameraUpload activeAccount:app.activeAccount] selector:selectorReadFolder];
                                        
                                    }];
        }

        if (!([_metadata.fileName isEqualToString:cameraUploadFolderName] == YES && [serverUrl isEqualToString:cameraUploadFolderPath] == YES)) {
            
            [actionSheet addButtonWithTitle:titoloLock
                                      image:[UIImage imageNamed:@"actionSheetLock"]
                            backgroundColor:[UIColor whiteColor]
                                     height: 50.0
                                       type:AHKActionSheetButtonTypeEncrypted
                                    handler:^(AHKActionSheet *as) {
                                        
                                        // close swipe
                                        [self setEditing:NO animated:YES];
                                        
                                        [self performSelector:@selector(comandoLockPassword) withObject:nil];
                                    }];
        }

        if (!([_metadata.fileName isEqualToString:cameraUploadFolderName] == YES && [serverUrl isEqualToString:cameraUploadFolderPath] == YES) && !lockDirectory && app.isCryptoCloudMode) {
            
            [actionSheet addButtonWithTitle:titoloCriptaDecripta
                                      image:[UIImage imageNamed:@"actionSheetCrypto"]
                            backgroundColor:[UIColor whiteColor]
                                     height: 50.0
                                       type:AHKActionSheetButtonTypeEncrypted
                                    handler:^(AHKActionSheet *as) {
                                        
                                        // close swipe
                                        [self setEditing:NO animated:YES];
                                        
                                        [self performSelector:@selector(encyptedDecryptedFolder) withObject:nil];
                                    }];
        }

        [actionSheet show];
    }
    
    /******************************************* FILE *******************************************/
    
    if ([_metadata.type isEqualToString: k_metadataType_file] && !_metadata.directory) {
        
        UIImage *iconHeader;
        
        // assegnamo l'immagine anteprima se esiste, altrimenti metti quella standars
        if ([[NSFileManager defaultManager] fileExistsAtPath:[NSString stringWithFormat:@"%@/%@.ico", app.directoryUser, _metadata.fileID]])
            iconHeader = [UIImage imageWithContentsOfFile:[NSString stringWithFormat:@"%@/%@.ico", app.directoryUser, _metadata.fileID]];
        else
            iconHeader = [UIImage imageNamed:_metadata.iconName];
        
        [actionSheet addButtonWithTitle: _metadata.fileNamePrint
                                  image: iconHeader
                        backgroundColor: [NCBrandColor sharedInstance].tabBar
                                 height: 50.0
                                   type: AHKActionSheetButtonTypeDisabled
                                handler: nil
        ];
        
        if (!_metadata.cryptated) {
            
            [actionSheet addButtonWithTitle:titleFavorite
                                      image:[CCGraphics changeThemingColorImage:[UIImage imageNamed:@"actionSheetFavorite"] color:[NCBrandColor sharedInstance].brand]
                            backgroundColor:[UIColor whiteColor]
                                     height: 50.0
                                       type:AHKActionSheetButtonTypeDefault
                                    handler:^(AHKActionSheet *as) {
                                        
                                        // close swipe
                                        [self setEditing:NO animated:YES];
                                        
                                        if (_metadata.favorite)
                                            [self  removeFavorite:_metadata];
                                        else
                                            [self addFavorite:_metadata];
                                    }];
        }

        if (_metadata.cryptated == NO) {
            
            [actionSheet addButtonWithTitle:NSLocalizedString(@"_share_", nil)
                                      image:[CCGraphics changeThemingColorImage:[UIImage imageNamed:@"actionSheetShare"] color:[NCBrandColor sharedInstance].brand]
                            backgroundColor:[UIColor whiteColor]
                                     height: 50.0
                                       type:AHKActionSheetButtonTypeDefault
                                    handler:^(AHKActionSheet *as) {
                                        
                                        // close swipe
                                        [self setEditing:NO animated:YES];
                                        
                                        [self openWindowShare:_metadata];
                                    }];
        }

        [actionSheet addButtonWithTitle:NSLocalizedString(@"_open_in_", nil)
                                  image:[CCGraphics changeThemingColorImage:[UIImage imageNamed:@"actionSheetOpenIn"] color:[NCBrandColor sharedInstance].brand]
                        backgroundColor:[UIColor whiteColor]
                                 height: 50.0
                                   type:AHKActionSheetButtonTypeDefault
                                handler:^(AHKActionSheet *as) {
                                    
                                    // close swipe
                                    [self setEditing:NO animated:YES];
                                    
                                    [self performSelector:@selector(openIn:) withObject:_metadata];
                                }];

        [actionSheet addButtonWithTitle:NSLocalizedString(@"_rename_", nil)
                                  image:[CCGraphics changeThemingColorImage:[UIImage imageNamed:@"actionSheetRename"] color:[NCBrandColor sharedInstance].brand]
                        backgroundColor:[UIColor whiteColor]
                                 height: 50.0
                                   type:AHKActionSheetButtonTypeDefault
                                handler:^(AHKActionSheet *as) {
                                    
                                    // close swipe
                                    [self setEditing:NO animated:YES];
                                    
                                    //chiediamo il nome del file
                                    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"_rename_",nil) message:nil delegate:self cancelButtonTitle:NSLocalizedString(@"_cancel_",nil) otherButtonTitles:NSLocalizedString(@"_save_", nil), nil];
                                    [alertView setAlertViewStyle:UIAlertViewStylePlainTextInput];
                                    alertView.tag = alertRename;
                                    UITextField *textField = [alertView textFieldAtIndex:0];
                                    textField.text = _metadata.fileNamePrint;
                                    [alertView show];
                                }];
        
        [actionSheet addButtonWithTitle:NSLocalizedString(@"_move_", nil)
                                  image:[CCGraphics changeThemingColorImage:[UIImage imageNamed:@"actionSheetMove"] color:[NCBrandColor sharedInstance].brand]
                        backgroundColor:[UIColor whiteColor]
                                 height: 50.0
                                   type:AHKActionSheetButtonTypeDefault
                                handler:^(AHKActionSheet *as) {
                                    
                                    // close swipe
                                    [self setEditing:NO animated:YES];
                                    
                                    [self moveOpenWindow:[[NSArray alloc] initWithObjects:indexPath, nil]];
                                }];
        
        if (recordLocalFile || [[NSFileManager defaultManager] fileExistsAtPath:[NSString stringWithFormat:@"%@/%@", app.directoryUser, _metadata.fileID]]) {
        
            [actionSheet addButtonWithTitle:NSLocalizedString(@"_remove_local_file_", nil)
                                      image:[CCGraphics changeThemingColorImage:[UIImage imageNamed:@"actionSheetRemoveLocal"] color:[NCBrandColor sharedInstance].brand]
                            backgroundColor:[UIColor whiteColor]
                                     height: 50.0
                                       type:AHKActionSheetButtonTypeDefault
                                    handler:^(AHKActionSheet *as) {
                                    
                                        // close swipe
                                        [self setEditing:NO animated:YES];
                                    
                                        [self performSelector:@selector(removeLocalFile:) withObject:_metadata];
                                    }];
        }

        if (app.isCryptoCloudMode) {
            
            [actionSheet addButtonWithTitle:titoloCriptaDecripta
                                      image:[UIImage imageNamed:@"actionSheetCrypto"]
                            backgroundColor:[UIColor whiteColor]
                                     height: 50.0
                                       type:AHKActionSheetButtonTypeEncrypted
                                    handler:^(AHKActionSheet *as) {
                                        
                                        // close swipe
                                        [self setEditing:NO animated:YES];
                                        
                                        [self performSelector:@selector(cmdEncryptedDecryptedFile) withObject:nil];
                                    }];
        }
        
        [actionSheet show];
    }
    
    /******************************************* TEMPLATE *******************************************/
    
    if ([_metadata.type isEqualToString: k_metadataType_template]) {
        
        [actionSheet addButtonWithTitle: _metadata.fileNamePrint
                                  image: [UIImage imageNamed:_metadata.iconName]
                        backgroundColor: [NCBrandColor sharedInstance].tabBar
                                 height: 50.0
                                   type: AHKActionSheetButtonTypeDisabled
                                handler: nil
        ];
        
        if ([_metadata.model isEqualToString:@"note"]) {
        
            [actionSheet addButtonWithTitle:NSLocalizedString(@"_rename_", nil)
                                      image:[UIImage imageNamed:@"actionSheetRename"]
                            backgroundColor:[UIColor whiteColor]
                                     height: 50.0
                                       type:AHKActionSheetButtonTypeDefault
                                    handler:^(AHKActionSheet *as) {
                                    
                                        // close swipe
                                        [self setEditing:NO animated:YES];
                                        
                                        //chiediamo il nome del file
                                        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"_rename_",nil) message:nil delegate:self cancelButtonTitle:NSLocalizedString(@"_cancel_",nil) otherButtonTitles:NSLocalizedString(@"_save_", nil), nil];
                                        [alertView setAlertViewStyle:UIAlertViewStylePlainTextInput];
                                        alertView.tag = alertRename;
                                        UITextField *textField = [alertView textFieldAtIndex:0];
                                        textField.text = _metadata.fileNamePrint;
                                        [alertView show];
                                }];
        }
        
        [actionSheet addButtonWithTitle:NSLocalizedString(@"_move_", nil)
                                  image:[UIImage imageNamed:@"actionSheetMove"]
                        backgroundColor:[UIColor whiteColor]
                                 height: 50.0
                                   type:AHKActionSheetButtonTypeDefault
                                handler:^(AHKActionSheet *as) {
                                    
                                    // close swipe
                                    [self setEditing:NO animated:YES];
                                    
                                    [self moveOpenWindow:[[NSArray alloc] initWithObjects:indexPath, nil]];
                                }];

        [actionSheet show];
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return NSLocalizedString(@"_delete_", nil);
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    CCMetadata *metadata = [self getMetadataFromSectionDataSource:indexPath];
    
    if (metadata == nil || metadata.errorPasscode || (metadata.cryptated && [metadata.title length] == 0) || metadata.sessionTaskIdentifier  >= 0 || metadata.sessionTaskIdentifier >= 0) return NO;
    else return YES;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath
{
    CCMetadata *metadata = [self getMetadataFromSectionDataSource:indexPath];
    
    if (metadata.errorPasscode || (metadata.cryptated && [metadata.title length] == 0) || metadata.sessionTaskIdentifier >= 0 || metadata.sessionTaskIdentifier >= 0) return UITableViewCellEditingStyleNone;
    else return UITableViewCellEditingStyleDelete;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    BOOL lockDirectory = NO;
    
    // Directory locked ?
    NSString *lockServerUrl = [CCUtility stringAppendServerUrl:[CCCoreData getServerUrlFromDirectoryID:_metadata.directoryID activeAccount:_metadata.account] addFileName:_metadata.fileNameData];
    
    if ([CCCoreData isDirectoryLock:lockServerUrl activeAccount:app.activeAccount] && [[CCUtility getBlockCode] length] && app.sessionePasscodeLock == nil) lockDirectory = YES;
    
    if (lockDirectory && editingStyle == UITableViewCellEditingStyleDelete) {
        
        [app messageNotification:@"_error_" description:@"_folder_blocked_" visible:YES delay:k_dismissAfterSecond type:TWMessageBarMessageTypeError errorCode:0];
        
        return;
    }

    if (editingStyle == UITableViewCellEditingStyleDelete) {
        
        _metadata = [self getMetadataFromSectionDataSource:indexPath];
        
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
        
        [alertController addAction: [UIAlertAction actionWithTitle:NSLocalizedString(@"_delete_", nil)
                                                             style:UIAlertActionStyleDestructive
                                                           handler:^(UIAlertAction *action) {
                                                               [self performSelector:@selector(deleteFile) withObject:nil];
                                                           }]];
        
        [alertController addAction: [UIAlertAction actionWithTitle:NSLocalizedString(@"_cancel_", nil)
                                                             style:UIAlertActionStyleCancel
                                                           handler:^(UIAlertAction *action) {
                                                               [alertController dismissViewControllerAnimated:YES completion:nil];
                                                           }]];
                
        alertController.popoverPresentationController.sourceView = self.view;
        alertController.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:indexPath];
        
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
            [alertController.view layoutIfNeeded];
        
        [self presentViewController:alertController animated:YES completion:nil];
    }
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark - ==== Datasource ====
#pragma --------------------------------------------------------------------------------------------

- (void)clearDateReadDataSource:(NSNotification *)notification
{
    _dateReadDataSource = Nil;
    [self reloadDatasource];
}

- (void)reloadDatasource
{
    [self reloadDatasource:_serverUrl fileID:nil selector:nil];
}

- (void)reloadDatasource:(NSString *)serverUrl fileID:(NSString *)fileID selector:(NSString *)selector
{
    // test
    if (app.activeAccount.length == 0 || serverUrl.length == 0)
        return;
    
    // Search Mode
    if(_isSearchMode) {
        
        if ([selector length] == 0 || [selector isEqualToString:selectorSearch]) {
        
            _sectionDataSource = [CCSectionMetadata creataDataSourseSectionMetadata:_searchResultMetadatas listProgressMetadata:nil groupByField:_directoryGroupBy replaceDateToExifDate:NO activeAccount:app.activeAccount];
            
        } else {
            
            [self readFolderWithForced:NO serverUrl:serverUrl];
        }
        
        [self tableViewReload];
        
        if ([_sectionDataSource.allRecordsDataSource count] == 0 && [_searchFileName length] >= k_minCharsSearch) {
            
            _noFilesSearchTitle = NSLocalizedString(@"_search_no_record_found_", nil);
            _noFilesSearchDescription = @"";
        }
        
        if ([_sectionDataSource.allRecordsDataSource count] == 0 && [_searchFileName length] < k_minCharsSearch) {
            
            _noFilesSearchTitle = @"";
            _noFilesSearchDescription = NSLocalizedString(@"_search_instruction_", nil);
        }
    
        [self.tableView reloadEmptyDataSet];
        
        return;
    }
    
    // Reload -> Self se non siamo nella dir appropriata cercala e se è in memoria reindirizza il reload
    if ([serverUrl isEqualToString:_serverUrl] == NO || _serverUrl == nil) {
        
        if ([selector isEqualToString:selectorDownloadSynchronize]) {
            [app.activeTransfers reloadDatasource];
        } else {
            CCMain *main = [app.listMainVC objectForKey:serverUrl];
            if (main) {
                [main reloadDatasource];
            } else {
                [self tableViewReload];
                [app.activeTransfers reloadDatasource];
            }
        }
        
        return;
    }
    
    // Offline folder ?
    _isOfflineServerUrl = [CCCoreData isOfflineDirectoryServerUrl:_serverUrl activeAccount:app.activeAccount];
    
    [app.activeTransfers reloadDatasource];
    
    // Settaggio variabili per le ottimizzazioni
    _directoryGroupBy = [CCUtility getGroupBySettings];
    _directoryOrder = [CCUtility getOrderSettings];
    
    // Controllo data lettura Data Source
    NSDate *dateDateRecordDirectory = [CCCoreData getDateReadDirectoryID:[CCCoreData getDirectoryIDFromServerUrl:_serverUrl activeAccount:app.activeAccount] activeAccount:app.activeAccount];
    
    if ([dateDateRecordDirectory compare:_dateReadDataSource] == NSOrderedDescending || dateDateRecordDirectory == nil || _dateReadDataSource == nil) {
        
        NSLog(@"[LOG] Rebuild Data Source File : %@", _serverUrl);

        _dateReadDataSource = [NSDate date];
    
        // Data Source
    
        NSArray *recordsTableMetadata = [CCCoreData getTableMetadataWithPredicate:[NSPredicate predicateWithFormat:@"(account == %@) AND (directoryID == %@)", app.activeAccount, [CCCoreData getDirectoryIDFromServerUrl:serverUrl activeAccount:app.activeAccount]] fieldOrder:[CCUtility getOrderSettings] ascending:[CCUtility getAscendingSettings]];
    
        _sectionDataSource = [CCSectionMetadata creataDataSourseSectionMetadata:recordsTableMetadata listProgressMetadata:nil groupByField:_directoryGroupBy replaceDateToExifDate:NO activeAccount:app.activeAccount];
        
    } else {
        
         NSLog(@"[LOG] [OPTIMIZATION] Rebuild Data Source File : %@ - %@", _serverUrl, _dateReadDataSource);
    }
    
    [self tableViewReload];    
}

- (NSArray *)getMetadatasFromSelectedRows:(NSArray *)selectedRows
{
    NSMutableArray *metadatas = [[NSMutableArray alloc] init];
    
    if (selectedRows.count > 0) {
    
        for (NSIndexPath *selectionIndex in selectedRows) {
            
            NSString *fileID = [[_sectionDataSource.sectionArrayRow objectForKey:[_sectionDataSource.sections objectAtIndex:selectionIndex.section]] objectAtIndex:selectionIndex.row];
            CCMetadata *metadata = [_sectionDataSource.allRecordsDataSource objectForKey:fileID];

            [metadatas addObject:metadata];
        }
    }
    
    return metadatas;
}

- (CCMetadata *)getMetadataFromSectionDataSource:(NSIndexPath *)indexPath
{
    NSInteger section = indexPath.section + 1;
    NSInteger row = indexPath.row + 1;
    
    NSInteger totSections =[_sectionDataSource.sections count] ;
    
    if ((totSections < section) || (section > totSections)) {
      
        NSLog(@"[LOG] %@", [NSString stringWithFormat:@"DEBUG [0] : error section, totSections = %lu - section = %lu", (long)totSections, (long)section]);
        return nil;
    }
    
    id valueSection = [_sectionDataSource.sections objectAtIndex:indexPath.section];
    
    NSArray *fileIDs = [_sectionDataSource.sectionArrayRow objectForKey:valueSection];
    
    if (fileIDs) {
        
        NSInteger totRows =[fileIDs count] ;
        
        if ((totRows < row) || (row > totRows)) {
            
            NSLog(@"[LOG] %@", [NSString stringWithFormat:@"DEBUG [1] : error row, totRows = %lu - row = %lu", (long)totRows, (long)row]);
            return nil;
        }

    } else {
        
        NSLog(@"[LOG] DEBUG [2] : fileIDs is NIL");
        return nil;
    }
    
    NSString *fileID = [fileIDs objectAtIndex:indexPath.row];
    
    return [_sectionDataSource.allRecordsDataSource objectForKey:fileID];
}

- (NSArray *)getMetadatasFromSectionDataSource:(NSInteger)section
{
    NSInteger totSections =[_sectionDataSource.sections count] ;
    
    if ((totSections < (section + 1)) || ((section + 1) > totSections)) {
        
#if DEBUG
        UIAlertView * alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"_error_", nil) message:[NSString stringWithFormat:@"DEBUG [3] : error section, totSections = %lu - section = %lu", (long)totSections, (long)section] delegate:nil cancelButtonTitle:nil otherButtonTitles:NSLocalizedString(@"_ok_", nil), nil];
        [alertView show];
#endif
        return nil;
    }
    
    id valueSection = [_sectionDataSource.sections objectAtIndex:section];
    
    return  [_sectionDataSource.sectionArrayRow objectForKey:valueSection];
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark - ==== Table ==== 
#pragma --------------------------------------------------------------------------------------------

- (void)tableViewSelect:(BOOL)edit
{
    // chiudiamo eventuali swipe aperti
    if (edit) [self.tableView setEditing:NO animated:NO];
    
    [self.tableView setAllowsMultipleSelectionDuringEditing:edit];
    [self.tableView setEditing:edit animated:YES];
    _isSelectedMode = edit;
    
    if (edit)
        [self setUINavigationBarSelected];
    else
        [self setUINavigationBarDefault];
    
    [self setTitle];
}

- (void)tableViewReload
{
    // ricordiamoci le row selezionate
    NSArray *indexPaths = [self.tableView indexPathsForSelectedRows];
    [self.tableView reloadData];
    
    for (NSIndexPath *path in indexPaths)
        [self.tableView selectRowAtIndexPath:path animated:NO scrollPosition:UITableViewScrollPositionNone];
    
    [self setTableViewFooter];
    
    if (self.tableView.editing)
        [self setTitle];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 60;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return [[_sectionDataSource.sectionArrayRow allKeys] count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [[_sectionDataSource.sectionArrayRow objectForKey:[_sectionDataSource.sections objectAtIndex:section]] count];
}
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    NSArray *sections = [_sectionDataSource.sectionArrayRow allKeys];
    NSString *sectionTitle = [sections objectAtIndex:section];
    
    if ([sectionTitle isKindOfClass:[NSString class]] && [sectionTitle rangeOfString:@"download"].location != NSNotFound) return 18.f;
    if ([sectionTitle isKindOfClass:[NSString class]] && [sectionTitle rangeOfString:@"upload"].location != NSNotFound) return 18.f;
    
    if ([_directoryGroupBy isEqualToString:@"none"] && [sections count] <= 1) return 0.0f;
    
    return 20.f;
}

-(UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    float shift;
    UIVisualEffectView *visualEffectView;
    
    // Titolo
    NSString *titleSection;
    
    // Controllo
    if ([_sectionDataSource.sections count] == 0)
        return nil;
    
    if ([[_sectionDataSource.sections objectAtIndex:section] isKindOfClass:[NSString class]]) titleSection = [_sectionDataSource.sections objectAtIndex:section];
    if ([[_sectionDataSource.sections objectAtIndex:section] isKindOfClass:[NSDate class]]) titleSection = [CCUtility getTitleSectionDate:[_sectionDataSource.sections objectAtIndex:section]];
    
    if ([titleSection isEqualToString:@"_none_"]) titleSection = @"";
    else if ([titleSection rangeOfString:@"download"].location != NSNotFound) titleSection = NSLocalizedString(@"_title_section_download_",nil);
    else if ([titleSection rangeOfString:@"upload"].location != NSNotFound) titleSection = NSLocalizedString(@"_title_section_upload_",nil);
    else titleSection = NSLocalizedString(titleSection,nil);
    
    // Formato titolo
    NSString *currentDevice = [CCUtility currentDevice];
    if ([currentDevice rangeOfString:@"iPad3"].location != NSNotFound) {
        
        visualEffectView = [[UIVisualEffectView alloc] init];
        visualEffectView.backgroundColor = [[NCBrandColor sharedInstance].brand colorWithAlphaComponent:0.3];
        
    } else {
        
        UIVisualEffect *blurEffect;
        blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleLight];
        visualEffectView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
        visualEffectView.backgroundColor = [[NCBrandColor sharedInstance].brand colorWithAlphaComponent:0.2];
    }
    
    if ([_directoryGroupBy isEqualToString:@"alphabetic"]) {
        
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) shift = - 35;
        else shift =  - 20;
        
    } else shift = - 10;
    
    // Title
    UILabel *titleLabel = [[UILabel alloc]initWithFrame:CGRectMake(10, -12, 0, 44)];
    titleLabel.backgroundColor = [UIColor clearColor];
    titleLabel.textColor = [UIColor blackColor];
    titleLabel.font = [UIFont systemFontOfSize:12];
    titleLabel.textAlignment = NSTextAlignmentLeft;
    titleLabel.text = titleSection;
    titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    [visualEffectView addSubview:titleLabel];
    
    // Elements
    UILabel *elementLabel= [[UILabel alloc]initWithFrame:CGRectMake(shift, -12, 0, 44)];
    elementLabel.backgroundColor = [UIColor clearColor];
    elementLabel.textColor = [UIColor blackColor];;
    elementLabel.font = [UIFont systemFontOfSize:12];
    elementLabel.textAlignment = NSTextAlignmentRight;
    elementLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    
    NSArray *metadatas = [self getMetadatasFromSectionDataSource:section];
    NSUInteger rowsCount = [metadatas count];
    
    if (rowsCount == 0) return nil;
    if (rowsCount == 1) elementLabel.text = [NSString stringWithFormat:@"%lu %@", (unsigned long)rowsCount,  NSLocalizedString(@"_element_",nil)];
    if (rowsCount > 1) elementLabel.text = [NSString stringWithFormat:@"%lu %@", (unsigned long)rowsCount,  NSLocalizedString(@"_elements_",nil)];
    
    [visualEffectView addSubview:elementLabel];
    
    return visualEffectView;
}

- (NSInteger)tableView:(UITableView *)tableView sectionForSectionIndexTitle:(NSString *)title atIndex:(NSInteger)index
{
    return [_sectionDataSource.sections indexOfObject:title];
}

- (NSArray *)sectionIndexTitlesForTableView:(UITableView *)tableView
{
    if ([_directoryGroupBy isEqualToString:@"alphabetic"])
        return [[UILocalizedIndexedCollation currentCollation] sectionIndexTitles];
    else
        return nil;
}

/*
-(void) tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if([indexPath row] == ((NSIndexPath*)[[tableView indexPathsForVisibleRows] lastObject]).row){
        
    }
}
*/

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *typeCell;
    NSString *dataFile;
    NSString *lunghezzaFile;
    
    CCMetadata *metadata = [self getMetadataFromSectionDataSource:indexPath];
    
    NSString *serverUrl = [CCCoreData getServerUrlFromDirectoryID:metadata.directoryID activeAccount:metadata.account];
    
    if ([metadata.session isEqualToString:@""] || metadata.session == nil) typeCell = @"CellMain";
    else typeCell = @"CellMainTransfer";
    
    if (!metadata)
        return [tableView dequeueReusableCellWithIdentifier:typeCell];
    
    CCCellMainTransfer *cell = (CCCellMainTransfer *)[tableView dequeueReusableCellWithIdentifier:typeCell forIndexPath:indexPath];
    
    // separator
    cell.separatorInset = UIEdgeInsetsMake(0.f, 60.f, 0.f, 0.f);
    
    // change color selection
    UIView *selectionColor = [[UIView alloc] init];
    selectionColor.backgroundColor = [[NCBrandColor sharedInstance] getColorSelectBackgrond];
    cell.selectedBackgroundView = selectionColor;
    
    if ([typeCell isEqualToString:@"CellMain"]) cell.backgroundColor = [UIColor whiteColor];
    if ([typeCell isEqualToString:@"CellMainTransfer"]) cell.backgroundColor = [NCBrandColor sharedInstance].transferBackground;
    
    // ----------------------------------------------------------------------------------------------------------
    // DEFAULT
    // ----------------------------------------------------------------------------------------------------------
    
    cell.fileImageView.image = nil;
    cell.statusImageView.image = nil;
    cell.offlineImageView.image = nil;
    cell.synchronizedImageView.image = nil;
    cell.sharedImageView.image = nil;
    
    cell.labelTitle.enabled = YES;
    cell.labelTitle.text = @"";
    cell.labelInfoFile.enabled = YES;
    cell.labelInfoFile.text = @"";
    
    cell.progressView.progress = 0.0;
    cell.progressView.hidden = YES;
    
    cell.cancelTaskButton.hidden = YES;
    cell.reloadTaskButton.hidden = YES;
    cell.stopTaskButton.hidden = YES;
    
    // Encrypted color
    if (metadata.cryptated) {
        cell.labelTitle.textColor = [NCBrandColor sharedInstance].cryptocloud;
    } else {
        cell.labelTitle.textColor = [UIColor blackColor];
    }
    
    // ----------------------------------------------------------------------------------------------------------
    // File Name & Folder
    // ----------------------------------------------------------------------------------------------------------
    
    // nome del file
    cell.labelTitle.text = metadata.fileNamePrint;
    
    // è una directory
    if (metadata.directory) {
        
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.labelInfoFile.text = [CCUtility dateDiff:metadata.date];
        
        lunghezzaFile = @" ";
                
        // ----------------------------------------------------------------------------------------------------------
        // Favorite Folder
        // ----------------------------------------------------------------------------------------------------------
        
        if (metadata.favorite) {
            
            cell.offlineImageView.image = [UIImage imageNamed:@"favorite"];
        }
        
    } else {
    
        // File                
        dataFile = [CCUtility dateDiff:metadata.date];
        lunghezzaFile = [CCUtility transformedSize:metadata.size];
        
        // Plist ancora da scaricare
        if (metadata.cryptated && [metadata.title length] == 0) {
            
            dataFile = @" ";
            lunghezzaFile = @" ";
        }
        
        TableLocalFile *recordLocalFile = [CCCoreData getLocalFileWithFileID:metadata.fileID activeAccount:app.activeAccount];
        
        NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
        [dateFormatter setDateStyle:NSDateFormatterShortStyle];
        [dateFormatter setTimeStyle:NSDateFormatterShortStyle];
        
        if ([metadata.type isEqualToString: k_metadataType_template] && [dataFile isEqualToString:@" "] == NO && [lunghezzaFile isEqualToString:@" "] == NO)
            cell.labelInfoFile.text = [NSString stringWithFormat:@"%@", dataFile];
        
        if ([metadata.type isEqualToString: k_metadataType_file] && [dataFile isEqualToString:@" "] == NO && [lunghezzaFile isEqualToString:@" "] == NO) {
            if (recordLocalFile && [[NSFileManager defaultManager] fileExistsAtPath:[NSString stringWithFormat:@"%@/%@", app.directoryUser, metadata.fileID]])
                cell.labelInfoFile.text = [NSString stringWithFormat:@"%@ • %@", dataFile, lunghezzaFile];
            else
                cell.labelInfoFile.text = [NSString stringWithFormat:@"%@ ◦ %@", dataFile, lunghezzaFile];
        }

        // Plist ancora da scaricare
        if ([dataFile isEqualToString:@" "] && [lunghezzaFile isEqualToString:@" "])
            cell.labelInfoFile.text = NSLocalizedString(@"_no_plist_pull_down_",nil);
    
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
    
    // ----------------------------------------------------------------------------------------------------------
    // File Image View
    // ----------------------------------------------------------------------------------------------------------

    // assegnamo l'immagine anteprima se esiste, altrimenti metti quella standars
    if ([[NSFileManager defaultManager] fileExistsAtPath:[NSString stringWithFormat:@"%@/%@.ico", app.directoryUser, metadata.fileID]]) {
        
        cell.fileImageView.image = [app.icoImagesCache objectForKey:metadata.fileID];
        
        if (cell.fileImageView.image == nil) {
            
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                
                UIImage *image = [UIImage imageWithContentsOfFile:[NSString stringWithFormat:@"%@/%@.ico", app.directoryUser, metadata.fileID]];
                
                [app.icoImagesCache setObject:image forKey:metadata.fileID];
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    
                    CCCellMainTransfer *cell = [tableView cellForRowAtIndexPath:indexPath];
                    
                    if (cell)
                        cell.fileImageView.image = image;
                });
            });
        }

    } else {
        
        if (metadata.directory)
            cell.fileImageView.image = [CCGraphics changeThemingColorImage:[UIImage imageNamed:metadata.iconName] color:[NCBrandColor sharedInstance].brand];
        else
            cell.fileImageView.image = [UIImage imageNamed:metadata.iconName];
        
        if (metadata.thumbnailExists)
            [[CCActions sharedInstance] downloadTumbnail:metadata delegate:self];
    }
    
    // ----------------------------------------------------------------------------------------------------------
    // Image Status cyptated & Lock Passcode
    // ----------------------------------------------------------------------------------------------------------
    
    // File Cyptated
    if (metadata.cryptated && metadata.directory == NO && [metadata.type isEqualToString: k_metadataType_template] == NO) {
     
        cell.statusImageView.image = [UIImage imageNamed:@"lock"];
    }
    
    // Directory con passcode lock attivato
    NSString *lockServerUrl = [CCUtility stringAppendServerUrl:serverUrl addFileName:metadata.fileNameData];
    if (metadata.directory && ([CCCoreData isDirectoryLock:lockServerUrl activeAccount:app.activeAccount] && [[CCUtility getBlockCode] length]))
        cell.statusImageView.image = [UIImage imageNamed:@"passcode"];
    
    // ----------------------------------------------------------------------------------------------------------
    // Offline
    // ----------------------------------------------------------------------------------------------------------

    BOOL isOfflineFile = [CCCoreData isOfflineLocalFileID:metadata.fileID activeAccount:app.activeAccount];
    
    if (isOfflineFile) {
        
        cell.offlineImageView.image = [UIImage imageNamed:@"offline"];
    }
    
    // ----------------------------------------------------------------------------------------------------------
    // Favorite
    // ----------------------------------------------------------------------------------------------------------
    
    if (metadata.favorite) {
        
        cell.offlineImageView.image = [UIImage imageNamed:@"favorite"];
    }
    
    // ----------------------------------------------------------------------------------------------------------
    // Share
    // ----------------------------------------------------------------------------------------------------------

    NSString *shareLink = [app.sharesLink objectForKey:[serverUrl stringByAppendingString:metadata.fileName]];
    NSString *shareUserAndGroup = [app.sharesUserAndGroup objectForKey:[serverUrl stringByAppendingString:metadata.fileName]];
    BOOL isShare = ([metadata.permissions length] > 0) && ([metadata.permissions rangeOfString:k_permission_shared].location != NSNotFound) && ([_fatherPermission rangeOfString:k_permission_shared].location == NSNotFound);
    BOOL isMounted = ([metadata.permissions length] > 0) && ([metadata.permissions rangeOfString:k_permission_mounted].location != NSNotFound) && ([_fatherPermission rangeOfString:k_permission_mounted].location == NSNotFound);
    
    // Aggiungiamo il Tap per le shared
    if (isShare || [shareLink length] > 0 || [shareUserAndGroup length] > 0 || isMounted) {
    
        if (isShare) {
       
            if (metadata.directory) {
                
                cell.fileImageView.image = [CCGraphics changeThemingColorImage:[UIImage imageNamed:@"folder_shared_with_me"] color:[NCBrandColor sharedInstance].brand];
                cell.sharedImageView.userInteractionEnabled = NO;
                
            } else {
            
                cell.sharedImageView.image = [CCGraphics changeThemingColorImage:[UIImage imageNamed:@"actionSheetShare"] color:[NCBrandColor sharedInstance].brand];
            
                UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapActionConnectionMounted:)];
                [tap setNumberOfTapsRequired:1];
                cell.sharedImageView.userInteractionEnabled = YES;
                [cell.sharedImageView addGestureRecognizer:tap];
            }
        }
        
        if (isMounted) {
            
            if (metadata.directory) {
                
                cell.fileImageView.image = [CCGraphics changeThemingColorImage:[UIImage imageNamed:@"folder_external"] color:[NCBrandColor sharedInstance].brand];
                cell.sharedImageView.userInteractionEnabled = NO;
                
            } else {
                
                cell.sharedImageView.image = [CCGraphics changeThemingColorImage:[UIImage imageNamed:@"shareMounted"] color:[NCBrandColor sharedInstance].brand];
                
                UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapActionConnectionMounted:)];
                [tap setNumberOfTapsRequired:1];
                cell.sharedImageView.userInteractionEnabled = YES;
                [cell.sharedImageView addGestureRecognizer:tap];
            }
        }
        
        if ([shareLink length] > 0 || [shareUserAndGroup length] > 0) {
        
            if (metadata.directory) {
                
                if ([shareLink length] > 0)
                    cell.fileImageView.image = [CCGraphics changeThemingColorImage:[UIImage imageNamed:@"folder_public"] color:[NCBrandColor sharedInstance].brand];
                if ([shareUserAndGroup length] > 0)
                    cell.fileImageView.image = [CCGraphics changeThemingColorImage:[UIImage imageNamed:@"folder_shared_with_me"] color:[NCBrandColor sharedInstance].brand];
                
                cell.sharedImageView.userInteractionEnabled = NO;
                
            } else {
                
                if ([shareLink length] > 0)
                    cell.sharedImageView.image = [CCGraphics changeThemingColorImage:[UIImage imageNamed:@"shareLink"] color:[NCBrandColor sharedInstance].brand];
                if ([shareUserAndGroup length] > 0)
                    cell.sharedImageView.image = [CCGraphics changeThemingColorImage:[UIImage imageNamed:@"actionSheetShare"] color:[NCBrandColor sharedInstance].brand];
                
                UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapActionShared:)];
                [tap setNumberOfTapsRequired:1];
                cell.sharedImageView.userInteractionEnabled = YES;
                [cell.sharedImageView addGestureRecognizer:tap];
            }
        }
        
    } else {
        
        cell.sharedImageView.userInteractionEnabled = NO;
    }
    
    // ----------------------------------------------------------------------------------------------------------
    // downloadFile
    // ----------------------------------------------------------------------------------------------------------
    
    if ([metadata.session length] > 0 && [metadata.session containsString:@"download"]) {
        
        if (metadata.cryptated) cell.statusImageView.image = [UIImage imageNamed:@"statusdownloadcrypto"];
        else cell.statusImageView.image = [UIImage imageNamed:@"statusdownload"];

        // sessionTaskIdentifier : RELOAD + STOP
        if (metadata.sessionTaskIdentifier != k_taskIdentifierDone) {
            
            if (metadata.cryptated)[cell.cancelTaskButton setBackgroundImage:[UIImage imageNamed:@"stoptaskcrypto"] forState:UIControlStateNormal];
            else [cell.cancelTaskButton setBackgroundImage:[UIImage imageNamed:@"stoptask"] forState:UIControlStateNormal];
            
            cell.cancelTaskButton.hidden = NO;

            if (metadata.cryptated)[cell.reloadTaskButton setBackgroundImage:[UIImage imageNamed:@"reloadtaskcrypto"] forState:UIControlStateNormal];
            else [cell.reloadTaskButton setBackgroundImage:[UIImage imageNamed:@"reloadtask"] forState:UIControlStateNormal];
            
            cell.reloadTaskButton.hidden = NO;
            
        }
        
        // sessionTaskIdentifierPlist : RELOAD
        if (metadata.sessionTaskIdentifierPlist != k_taskIdentifierDone) {
            
            if (metadata.cryptated)[cell.reloadTaskButton setBackgroundImage:[UIImage imageNamed:@"reloadtaskcrypto"] forState:UIControlStateNormal];
            else [cell.reloadTaskButton setBackgroundImage:[UIImage imageNamed:@"reloadtask"] forState:UIControlStateNormal];
            
            cell.reloadTaskButton.hidden = NO;
        }

        cell.labelInfoFile.text = [NSString stringWithFormat:@"%@", lunghezzaFile];
        
        float progress = [[app.listProgressMetadata objectForKey:metadata.fileID] floatValue];
        if (progress > 0) {
            
            if (metadata.cryptated) cell.progressView.progressTintColor = [NCBrandColor sharedInstance].cryptocloud;
            else cell.progressView.progressTintColor = [UIColor blackColor];
            
            cell.progressView.progress = progress;
            cell.progressView.hidden = NO;
        }

        // ----------------------------------------------------------------------------------------------------------
        // downloadFile Error
        // ----------------------------------------------------------------------------------------------------------
        
        if (metadata.sessionTaskIdentifier == k_taskIdentifierError || metadata.sessionTaskIdentifierPlist == k_taskIdentifierError) {
            
            cell.statusImageView.image = [UIImage imageNamed:@"statuserror"];
            
            if ([metadata.sessionError length] == 0)
                cell.labelInfoFile.text = [NSString stringWithFormat:@"%@, %@", NSLocalizedString(@"_error_",nil), NSLocalizedString(@"_file_not_downloaded_",nil)];
            else
                cell.labelInfoFile.text = [CCError manageErrorKCF:[metadata.sessionError integerValue] withNumberError:NO];
        }
    }    
    
    // ----------------------------------------------------------------------------------------------------------
    // uploadFile
    // ----------------------------------------------------------------------------------------------------------
    
    if ([metadata.session length] > 0 && [metadata.session rangeOfString:@"upload"].location != NSNotFound) {
        
        if (metadata.cryptated) cell.statusImageView.image = [UIImage imageNamed:@"statusuploadcrypto"];
        else cell.statusImageView.image = [UIImage imageNamed:@"statusupload"];
        
        if (metadata.cryptated)[cell.cancelTaskButton setBackgroundImage:[UIImage imageNamed:@"removetaskcrypto"] forState:UIControlStateNormal];
        else [cell.cancelTaskButton setBackgroundImage:[UIImage imageNamed:@"removetask"] forState:UIControlStateNormal];
        cell.cancelTaskButton.hidden = NO;
        
        if (metadata.sessionTaskIdentifier == k_taskIdentifierStop) {
            
            if (metadata.cryptated)[cell.reloadTaskButton setBackgroundImage:[UIImage imageNamed:@"reloadtaskcrypto"] forState:UIControlStateNormal];
            else [cell.reloadTaskButton setBackgroundImage:[UIImage imageNamed:@"reloadtask"] forState:UIControlStateNormal];
            
            if (metadata.cryptated) cell.statusImageView.image = [UIImage imageNamed:@"statusstopcrypto"];
            else cell.statusImageView.image = [UIImage imageNamed:@"statusstop"];
            
            cell.reloadTaskButton.hidden = NO;
            cell.stopTaskButton.hidden = YES;
            
        } else {
            
            if (metadata.cryptated)[cell.stopTaskButton setBackgroundImage:[UIImage imageNamed:@"stoptaskcrypto"] forState:UIControlStateNormal];
            else [cell.stopTaskButton setBackgroundImage:[UIImage imageNamed:@"stoptask"] forState:UIControlStateNormal];
            
            cell.stopTaskButton.hidden = NO;
            cell.reloadTaskButton.hidden = YES;
        }
        
        // se non c'è una preview in bianconero metti l'immagine di default
        if ([[NSFileManager defaultManager] fileExistsAtPath:[NSString stringWithFormat:@"%@/%@.ico", app.directoryUser, metadata.fileID]] == NO)
            cell.fileImageView.image = [CCGraphics changeThemingColorImage:[UIImage imageNamed:@"uploaddisable"] color:[NCBrandColor sharedInstance].brand];
        
        cell.labelTitle.enabled = NO;
        cell.labelInfoFile.text = [NSString stringWithFormat:@"%@", lunghezzaFile];
        
        float progress = [[app.listProgressMetadata objectForKey:metadata.fileID] floatValue];
        if (progress > 0) {
            
            if (metadata.cryptated) cell.progressView.progressTintColor = [NCBrandColor sharedInstance].cryptocloud;
            else cell.progressView.progressTintColor = [UIColor blackColor];
            
            cell.progressView.progress = progress;
            cell.progressView.hidden = NO;
        }
        
        // ----------------------------------------------------------------------------------------------------------
        // uploadFileError
        // ----------------------------------------------------------------------------------------------------------
    
        if (metadata.sessionTaskIdentifier == k_taskIdentifierError || metadata.sessionTaskIdentifierPlist == k_taskIdentifierError) {
        
            cell.labelTitle.enabled = NO;
            cell.statusImageView.image = [UIImage imageNamed:@"statuserror"];
        
            if ([metadata.sessionError length] == 0)
                cell.labelInfoFile.text = [NSString stringWithFormat:@"%@, %@", NSLocalizedString(@"_error_",nil), NSLocalizedString(@"_file_not_uploaded_",nil)];
            else
                cell.labelInfoFile.text = [CCError manageErrorKCF:[metadata.sessionError integerValue] withNumberError:NO];
        }
    }

    [cell.reloadTaskButton addTarget:self action:@selector(reloadTaskButton:withEvent:) forControlEvents:UIControlEventTouchUpInside];
    [cell.cancelTaskButton addTarget:self action:@selector(cancelTaskButton:withEvent:) forControlEvents:UIControlEventTouchUpInside];
    [cell.stopTaskButton addTarget:self action:@selector(stopTaskButton:withEvent:) forControlEvents:UIControlEventTouchUpInside];

    return cell;
}

- (void)setTableViewFooter
{
    UIView *footerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 40)];
    [footerView setAutoresizingMask:UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin];
    
    UILabel *footerLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 0, 40)];
    [footerLabel setAutoresizingMask:UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin];
    
    UIFont *appFont = [UIFont systemFontOfSize:12];
    
    footerLabel.font = appFont;
    footerLabel.textColor = [UIColor grayColor];
    footerLabel.backgroundColor = [UIColor clearColor];
    footerLabel.textAlignment = NSTextAlignmentCenter;
    
    NSString *folders;
    NSString *files;
    NSString *footerText;
    
    if (_sectionDataSource.directories > 1) {
        folders = [NSString stringWithFormat:@"%ld %@", (long)_sectionDataSource.directories, NSLocalizedString(@"_folders_", nil)];
    } else if (_sectionDataSource.directories == 1){
        folders = [NSString stringWithFormat:@"%ld %@", (long)_sectionDataSource.directories, NSLocalizedString(@"_folder_", nil)];
    } else {
        folders = @"";
    }
    
    if (_sectionDataSource.files > 1) {
        files = [NSString stringWithFormat:@"%ld %@ %@", (long)_sectionDataSource.files, NSLocalizedString(@"_files_", nil), [CCUtility transformedSize:_sectionDataSource.totalSize]];
    } else if (_sectionDataSource.files == 1){
        files = [NSString stringWithFormat:@"%ld %@ %@", (long)_sectionDataSource.files, NSLocalizedString(@"_file_", nil), [CCUtility transformedSize:_sectionDataSource.totalSize]];
    } else {
        files = @"";
    }
    
    if ([folders isEqualToString:@""]) {
        footerText = files;
    } else if ([files isEqualToString:@""]) {
        footerText = folders;
    } else {
        footerText = [NSString stringWithFormat:@"%@, %@", folders, files];
    }
    
    footerLabel.text = footerText;
    
    [footerView addSubview:footerLabel];
    [self.tableView setTableFooterView:footerView];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *textMessage;
    
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    
    // se non può essere selezionata deseleziona
    if ([cell isEditing] == NO)
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    // se siamo in modalità editing impostiamo il titolo dei selezioati e usciamo subito
    if (self.tableView.editing) {
        
        [self setTitle];
        return;
    }
    
    // test crash
    NSArray *metadatas = [_sectionDataSource.sectionArrayRow objectForKey:[_sectionDataSource.sections objectAtIndex:indexPath.section]];
    if (indexPath.row >= [metadatas count]) return;
    
    // settiamo il record file.
    _metadata = [self getMetadataFromSectionDataSource:indexPath];
    
    //
    NSString *serverUrl = [CCCoreData getServerUrlFromDirectoryID:_metadata.directoryID activeAccount:_metadata.account];
    
    // se è in corso una sessione
    if ([_metadata.session length] > 0) return;
    
    if (_metadata.errorPasscode) {
            
        // se UUID è nil lo sta ancora caricando quindi esci
        if (!_metadata.uuid) return;
        
        // esiste un hint ??
        NSString *hint = [[CCCrypto sharedManager] getHintFromFile:_metadata.fileName isLocal:NO directoryUser:app.directoryUser];
        
        // qui !! la richiesta della nuova passcode
        if ([_metadata.uuid isEqualToString:[CCUtility getUUID]]) {
            
            // stesso UUID ... la password è stata modificata !!!!!!
            
            if (hint) textMessage = [NSString stringWithFormat:NSLocalizedString(@"_same_device_different_passcode_hint_",nil), hint];
            else textMessage = NSLocalizedString(@"_same_device_different_passcode_", nil);
            
            UIAlertView * alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"_error_", nil) message:textMessage delegate:nil cancelButtonTitle:nil otherButtonTitles:NSLocalizedString(@"_ok_", nil), nil];
            [alertView show];
                
        } else {
                
            // UUID diverso.
            
            if (hint) textMessage = [NSString stringWithFormat:NSLocalizedString(@"_file_encrypted_another_device_hint_",nil), _metadata.nameCurrentDevice, hint];
            else textMessage = [NSString stringWithFormat:NSLocalizedString(@"_file_encrypted_another_device_",nil), _metadata.nameCurrentDevice];
            
            UIAlertView * alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"_error_", nil) message:textMessage delegate:nil cancelButtonTitle:nil otherButtonTitles:NSLocalizedString(@"_ok_", nil), nil];
            [alertView show];
        }
            
        // chiediamo la passcode e ricarichiamo tutto.
        CCBKPasscode *viewController = [[CCBKPasscode alloc] initWithNibName:nil bundle:nil];
        viewController.delegate = self;
        viewController.fromType = CCBKPasscodeFromPasscode;
        viewController.passcodeStyle = BKPasscodeInputViewNormalPasscodeStyle;
        viewController.passcodeInputView.maximumLength = 64;
        viewController.type = BKPasscodeViewControllerCheckPasscodeType;
        viewController.inputViewTitlePassword = NO;
        
        viewController.title = [NCBrandOptions sharedInstance].brand;
        viewController.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(passcodeViewCloseButtonPressed:)];
        viewController.navigationItem.leftBarButtonItem.tintColor = [NCBrandColor sharedInstance].cryptocloud;

        UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:viewController];
            
        [self presentViewController:navigationController animated:YES completion:nil];
    }
    
    // modello o plist con il title a 0 allora è andato storto qualcosa ... ricaricalo
    if (_metadata.cryptated && [_metadata.title length] == 0) {
    
        NSString* selector;
        
        if ([_metadata.type isEqualToString: k_metadataType_template]) selector = selectorLoadModelView;
        else selector = selectorLoadPlist;
        
        [[CCNetworking sharedNetworking] downloadFile:_metadata serverUrl:serverUrl downloadData:NO downloadPlist:YES selector:selector selectorPost:nil session:k_download_session taskStatus:k_taskStatusResume delegate:self];
        
        return;
    }
        
    // se il plist è caricato ed è un modello aprilo
    if ([_metadata.type isEqualToString:k_metadataType_template]) [self openModel:_metadata.model isNew:false];
    
    // file
    if (_metadata.directory == NO && _metadata.errorPasscode == NO && [_metadata.type isEqualToString: k_metadataType_file]) {
        
        // se il file esiste andiamo direttamente al delegato altrimenti carichiamolo
        if ([[NSFileManager defaultManager] fileExistsAtPath:[NSString stringWithFormat:@"%@/%@", app.directoryUser, _metadata.fileID]]) {
                            
            [self downloadFileSuccess:_metadata.fileID serverUrl:serverUrl selector:selectorLoadFileView selectorPost:nil];
            
        } else {
                
            [[CCNetworking sharedNetworking] downloadFile:_metadata serverUrl:serverUrl downloadData:YES downloadPlist:NO selector:selectorLoadFileView selectorPost:nil session:k_download_session taskStatus:k_taskStatusResume delegate:self];
            
            NSIndexPath *indexPath = [_sectionDataSource.fileIDIndexPath objectForKey:_metadata.fileID];
            if (indexPath) [self.tableView reloadRowsAtIndexPaths:[NSArray arrayWithObjects:indexPath, nil] withRowAnimation:UITableViewRowAnimationAutomatic];
        }
    }
    
    if (_metadata.directory) [self performSegueDirectoryWithControlPasscode:true];
}

- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(nonnull NSIndexPath *)indexPath
{
    [self setTitle];
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Synchronize Folder Cell =====
#pragma --------------------------------------------------------------------------------------------

- (void)synchronizeFolderGraphicsServerUrl:(NSString *)serverUrl animation:(BOOL)animation
{
    BOOL cryptated = NO;
    CCCellMain *cell;
    
    for (NSString* fileID in _sectionDataSource.allRecordsDataSource) {
        
        CCMetadata *recordMetadata = [_sectionDataSource.allRecordsDataSource objectForKey:fileID];
        
        if (recordMetadata.directory == NO)
            continue;
        
        if ([[CCUtility stringAppendServerUrl:_serverUrl addFileName:recordMetadata.fileNameData] isEqualToString:serverUrl]) {
            
            NSIndexPath *indexPath = [_sectionDataSource.fileIDIndexPath objectForKey:recordMetadata.fileID];
            cell = (CCCellMain *)[self.tableView cellForRowAtIndexPath:indexPath];
            cryptated = recordMetadata.cryptated;
                
            break;
        }
    }

    if (!cell)
        return;
    
    if (animation) {
        
        NSURL *myURL;
        
        if (cryptated)
            myURL = [[NSBundle mainBundle] URLForResource: @"synchronizedcrypto" withExtension:@"gif"];
        else
            myURL = [[NSBundle mainBundle] URLForResource: @"synchronized" withExtension:@"gif"];        
        
    } else {
        
        cell.synchronizedImageView.image = nil;
    }
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Navigation ====
#pragma --------------------------------------------------------------------------------------------

- (BOOL)shouldPerformSegue
{
    // if background return
    if ([[UIApplication sharedApplication] applicationState] == UIApplicationStateBackground) return NO;
    
    if (self.view.window == NO)
        return NO;
    
    // Collapsed ma siamo già in detail esci
    if (self.splitViewController.isCollapsed)
        if (_detailViewController.isViewLoaded && _detailViewController.view.window) return NO;
    
    // Video in esecuzione esci
    if (_detailViewController.photoBrowser.currentVideoPlayerViewController.isViewLoaded && _detailViewController.photoBrowser.currentVideoPlayerViewController.view.window) return NO;
    
    return YES;
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    id viewController = segue.destinationViewController;
    NSMutableArray *allRecordsDataSourceImagesVideos = [NSMutableArray new];
    CCMetadata *metadata;
    
    if ([viewController isKindOfClass:[UINavigationController class]]) {
        
        UINavigationController *nav = viewController;
        _detailViewController = (CCDetail *)nav.topViewController;
        
    } else {
        
        _detailViewController = segue.destinationViewController;
    }
    
    if ([sender isKindOfClass:[CCMetadata class]]) {
    
        metadata = sender;
        [allRecordsDataSourceImagesVideos addObject:sender];
        
    } else {
        
        metadata = _metadata;
        
        for (NSString *fileID in _sectionDataSource.allFileID) {
            CCMetadata *metadata = [_sectionDataSource.allRecordsDataSource objectForKey:fileID];
            if ([metadata.typeFile isEqualToString: k_metadataTypeFile_image] || [metadata.typeFile isEqualToString: k_metadataTypeFile_video])
                [allRecordsDataSourceImagesVideos addObject:metadata];
        }
    }
    
    _detailViewController.metadataDetail = metadata;
    _detailViewController.dataSourceImagesVideos = allRecordsDataSourceImagesVideos;
    _detailViewController.dateFilterQuery = nil;
    _detailViewController.isCameraUpload = NO;
    
    [_detailViewController setTitle:metadata.fileNamePrint];
}

// can i go to next viewcontroller
- (void)performSegueDirectoryWithControlPasscode:(BOOL)controlPasscode
{
    NSString *nomeDir;

    if(self.tableView.editing == NO && _metadata.errorPasscode == NO){
        
        NSString *serverUrl = [CCCoreData getServerUrlFromDirectoryID:_metadata.directoryID activeAccount:_metadata.account];
        NSString *lockServerUrl = [CCUtility stringAppendServerUrl:serverUrl addFileName:_metadata.fileNameData];
        
        // SE siamo in presenza di una directory bloccata E è attivo il block E la sessione password Lock è senza data ALLORA chiediamo la password per procedere
        if ([CCCoreData isDirectoryLock:lockServerUrl activeAccount:app.activeAccount] && [[CCUtility getBlockCode] length] && app.sessionePasscodeLock == nil && controlPasscode) {
            
            CCBKPasscode *viewController = [[CCBKPasscode alloc] initWithNibName:nil bundle:nil];
            viewController.delegate = self;
            viewController.fromType = CCBKPasscodeFromLockDirectory;
            viewController.type = BKPasscodeViewControllerCheckPasscodeType;
            viewController.inputViewTitlePassword = YES;
            
            if ([CCUtility getSimplyBlockCode]) {
                
                viewController.passcodeStyle = BKPasscodeInputViewNumericPasscodeStyle;
                viewController.passcodeInputView.maximumLength = 6;
                
            } else {
                
                viewController.passcodeStyle = BKPasscodeInputViewNormalPasscodeStyle;
                viewController.passcodeInputView.maximumLength = 64;
            }

            BKTouchIDManager *touchIDManager = [[BKTouchIDManager alloc] initWithKeychainServiceName:k_serviceShareKeyChain];
            touchIDManager.promptText = NSLocalizedString(@"_scan_fingerprint_", nil);
            viewController.touchIDManager = touchIDManager;
            
            viewController.title = NSLocalizedString(@"_folder_blocked_", nil); 
            viewController.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(passcodeViewCloseButtonPressed:)];
            viewController.navigationItem.leftBarButtonItem.tintColor = [NCBrandColor sharedInstance].cryptocloud;
            
            UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:viewController];
            [self presentViewController:navController animated:YES completion:nil];
            
            return;
        }
        
        if (_metadata.cryptated) nomeDir = [_metadata.fileName substringToIndex:[_metadata.fileName length]-6];
        else nomeDir = _metadata.fileName;
        
        NSString *serverUrlPush = [CCUtility stringAppendServerUrl:serverUrl addFileName:nomeDir];
        
        CCMain *viewController = [app.listMainVC objectForKey:serverUrlPush];
        
        if (viewController.isViewLoaded == false || viewController == nil) {
            
            viewController = [[UIStoryboard storyboardWithName:@"Main" bundle:nil] instantiateViewControllerWithIdentifier:@"CCMainVC"];
            
            viewController.isFolderEncrypted = _metadata.cryptated;
            viewController.serverUrl = serverUrlPush;
            viewController.titleMain = _metadata.fileNamePrint;
            viewController.textBackButton = _titleMain;
            
            // save self
            [app.listMainVC setObject:viewController forKey:serverUrlPush];
        }
        
        // OFF SearchBar
        [viewController cancelSearchBar];
        
        [self.navigationController pushViewController:viewController animated:YES];
    }
}

@end
