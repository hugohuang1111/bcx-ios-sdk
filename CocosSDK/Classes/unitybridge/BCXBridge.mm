#import "BCXBridge.h"
#import "BCXBridgeListener.h"
#import <objc/runtime.h>
//#import "CocosSDK.h"
#import "CocosSDK/CocosSDK.h"

BCXBridgeIOS::BCXBridgeListener* bcxBridgeListener = nullptr;
NSString* dic2str(NSDictionary *dic) {
    NSError *error = nil;
    NSData *jsonData = nil;
    jsonData = [NSJSONSerialization dataWithJSONObject:dic options:0 error:&error];
    if ([jsonData length] == 0 || error != nil) {
        return @"";
    }
    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    return jsonString;
}

NSString* response2str(id responseObject) {
    NSString* json = @"{}";
    if (nil == responseObject) {
        return json;
    }
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    if ([responseObject isKindOfClass:[NSDictionary class]]) {
        json = dic2str(responseObject);
    } else {
        [dict setObject:[NSNumber numberWithInt:1] forKey: @"code"];
        if ([responseObject isKindOfClass:[NSArray class]]) {
            NSArray* arr = responseObject;
            NSMutableArray *marr = [NSMutableArray array];
            for (id item in arr) {
                if (![item isKindOfClass: [NSNull class]]) {
                    [marr addObject:item];
                }
            }

            [dict setObject:marr forKey: @"data"];
        } else {
            [dict setObject:responseObject forKey: @"data"];
        }
        json = dic2str(dict);
    }
    return json;
}

NSString* NSError2str(NSError* error) {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    [dict setObject: [NSNumber numberWithInteger: error.code] forKey: @"code"];
    [dict setObject: error.description forKey: @"data"];
    return dic2str(dict);
}

void BCX_set_unity_callback(void* callback) {
    if (nullptr == bcxBridgeListener) {
        bcxBridgeListener = new BCXBridgeIOS::BCXBridgeListener();
    }
    bcxBridgeListener->setUnityCallback((BCXBridgeIOS::BCXBridgeListener::tBCXBridgeUnityCallback)callback);
}

void BCX_reflectionCall(const char* json) {
    NSString* jsonStr = [NSString stringWithUTF8String:json];
    NSData *jsonData = [jsonStr dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *dic = [NSJSONSerialization JSONObjectWithData:jsonData
                                                        options:1
                                                          error:nil];
    if(nil == dic || 0 == [dic count]) {
        NSLog(@"parse json failed");
        return;
    }
    NSString* f = [dic valueForKey:@"f"];
    NSArray* p = [dic valueForKey:@"p"];
    NSString* fsignature = [NSString stringWithFormat:@"%@:", f];

    CocosSDK* bcxSDK = [CocosSDK shareInstance];
    int i=0;
    unsigned int mc = 0;
    bool bHandle = false;
    Method * mlist = class_copyMethodList(object_getClass(bcxSDK), &mc);
    for(i=0; i<mc; i++) {
        Method method = mlist[i];
        SEL mSel = method_getName(method);
        NSString* mName = [NSString stringWithUTF8String: sel_getName(mSel)];
        if ([mName hasPrefix:fsignature]) {
            if([bcxSDK respondsToSelector:mSel]) {
                //unsigned int argsCount = method_getNumberOfArguments(method);
                char returnType;
                method_getReturnType(method, &returnType, 1);

                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:[bcxSDK methodSignatureForSelector:mSel]];
                [inv setSelector:mSel];
                [inv setTarget:bcxSDK];
                int idx = 0;
                if (nullptr != p) {
                    for (idx = 0; idx < [p count]; idx++) {
                        id param = p[idx];
                        if ([param isKindOfClass: [NSArray class]]) {
                            [inv setArgument:&param atIndex:idx + 2];
                        } else if ([param isKindOfClass: [NSString class]]) {
                            [inv setArgument:&param atIndex:idx + 2];
                        } else if ([param isKindOfClass: [NSNumber class]]) {
                            NSInteger nsint = ((NSNumber*)param).integerValue;
                            [inv setArgument:&nsint atIndex:idx + 2];
                        } else {
                            NSLog(@"Unknown param type:%@", [param class]);
                        }
                    }
                }
                if ('v' == returnType) {
                    SuccessBlock sucBlock = nil;
                    Error errBlock = nil;
                    sucBlock = ^(id responseObject){
                        NSString* json = response2str(responseObject);
                        NSLog(@"success block:%@ => %@", f, json);
                        bcxBridgeListener->notifyUnity(f.UTF8String, json.UTF8String);
                        if (nil != sucBlock) Block_release(sucBlock);
                        if (nil != errBlock) Block_release(errBlock);
                    };
                    errBlock = ^(NSError *error){
                        NSString* json = NSError2str(error);
                        NSLog(@"error block:%@ => %@", f, json);
                        bcxBridgeListener->notifyUnity(f.UTF8String, json.UTF8String);
                        if (nil != sucBlock) Block_release(sucBlock);
                        if (nil != errBlock) Block_release(errBlock);
                    };
                    Block_copy((__bridge void *)sucBlock);
                    Block_copy((__bridge void *)errBlock);
                    [inv setArgument:&sucBlock atIndex:idx + 2];
                    [inv setArgument:&errBlock atIndex:idx + 3];
                }

                [inv retainArguments];
                [inv invoke];
                bHandle = true;
                break;
            }
        }
    }
    free(mlist);
    if (!bHandle) {
        NSLog(@"ERROR, %@ not invoke", f);
    }
}

void BCX_connect(const char* chainId,
                 const char* nodeUrlsString,
                 const char* faucetUrl,
                 const char* coreAsset,
                 bool isOpenLog) {
    [[CocosSDK shareInstance] Cocos_OpenLog: isOpenLog];
    [[CocosSDK shareInstance] Cocos_ConnectWithNodeUrl: [NSString stringWithUTF8String:nodeUrlsString]
                                             Fauceturl: [NSString stringWithUTF8String:faucetUrl]
                                               TimeOut: 5
                                             CoreAsset: [NSString stringWithUTF8String:coreAsset]
                                               ChainId: [NSString stringWithUTF8String:chainId]
                                       ConnectedStatus:^(WebsocketConnectStatus connectStatus) {
                                           if (nullptr == bcxBridgeListener) {
                                               return ;
                                           }
                                           NSMutableDictionary *dict = [NSMutableDictionary dictionary];
                                           if (WebsocketConnectStatusConnected == connectStatus) {
                                               [dict setObject:[NSNumber numberWithInt:1] forKey: @"code"];
                                           } else {
                                               [dict setObject:[NSNumber numberWithInt:0] forKey: @"code"];
                                           }
                                           bcxBridgeListener->notifyUnity("connect", dic2str(dict).UTF8String);
                                       }];
    NSLog(@"BCX iOS SDK Version: %@", [CocosSDK shareInstance].Cocos_SdkCurentVersion);
}

void BCX_get_version_info() {
    if (nullptr == bcxBridgeListener) {
        return;
    }
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    [dict setObject: [NSNumber numberWithInt:1] forKey: @"code"];
    [dict setObject: [CocosSDK shareInstance].Cocos_SdkCurentVersion forKey: @"data"];
    bcxBridgeListener->notifyUnity("get_version_info", dic2str(dict).UTF8String);
}

void BCX_create_account(const char* account, const char* password, const char* accountType, bool isAutoLogin) {
    if (nullptr == bcxBridgeListener) {
        return;
    }
    NSString* accType = [NSString stringWithUTF8String:accountType];
    CocosWalletMode m = CocosWalletModeAccount;
    if (NSOrderedSame == [@"WALLET" caseInsensitiveCompare:accType]) {
        m = CocosWalletModeWallet;
    }
    [[CocosSDK shareInstance] Cocos_CreateAccountWalletMode: m
                                                AccountName: [NSString stringWithUTF8String:account]
                                                   Password: [NSString stringWithUTF8String:password]
                                                  AutoLogin: isAutoLogin
                                                    Success: ^(id responseObject) {
                                                        bcxBridgeListener->notifyUnity("create_account", response2str(responseObject).UTF8String);
                                                    }
                                                      Error: ^(NSError *error) {
                                                          bcxBridgeListener->notifyUnity("create_account", NSError2str(error).UTF8String);
                                                      }];
}


/*
void BCX_calculate_invoking_contract_fee(const char* account,
                                         const char* feeAssetSymbol,
                                         const char* contractId,
                                         const char* functionName,
                                         const char* params) {
    if (nullptr == bcxBridgeListener) {
        return;
    }
    NSString* nsParams = [NSString stringWithUTF8String:params];
    [[CocosSDK shareInstance] Cocos_GetCallContractFee: [NSString stringWithUTF8String:contractId]
                                   ContractMethodParam: [nsParams componentsSeparatedByString: @","]
                                        ContractMethod: [NSString stringWithUTF8String:functionName]
                                         CallerAccount: [NSString stringWithUTF8String:account]
                                        feePayingAsset: [NSString stringWithUTF8String:feeAssetSymbol]
                                               Success: ^(id responseObject) {
                                                   bcxBridgeListener->notifyUnity("calculate_invoking_contract_fee", response2str(responseObject).UTF8String);
                                               }
                                                 Error: ^(NSError *error) {
                                                     bcxBridgeListener->notifyUnity("calculate_invoking_contract_fee", NSError2str(error).UTF8String);
                                                 }];
}

void BCX_invoking_contract(const char* account,
                           const char* password,
                           const char* feeAssetSymbol,
                           const char* contractId,
                           const char* functionName,
                           const char* params) {
    if (nullptr == bcxBridgeListener) {
        return;
    }
    NSString* nsParams = [NSString stringWithUTF8String:params];
    [[CocosSDK shareInstance] Cocos_CallContract: [NSString stringWithUTF8String:contractId]
                             ContractMethodParam: [nsParams componentsSeparatedByString: @","]
                                  ContractMethod: [NSString stringWithUTF8String:functionName]
                                   CallerAccount: [NSString stringWithUTF8String:account]
                                  feePayingAsset: [NSString stringWithUTF8String:feeAssetSymbol]
                                        Password: [NSString stringWithUTF8String:password]
                                         Success: ^(id responseObject) {
                                             bcxBridgeListener->notifyUnity("invoking_contract", response2str(responseObject).UTF8String);
                                         }
                                           Error: ^(NSError *error) {
                                               bcxBridgeListener->notifyUnity("invoking_contract", NSError2str(error).UTF8String);
                                           }];
}
*/

