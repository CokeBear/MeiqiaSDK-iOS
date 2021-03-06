//
//  MQServiceToViewInterface.m
//  MQChatViewControllerDemo
//
//  Created by ijinmao on 15/11/5.
//  Copyright © 2015年 ijinmao. All rights reserved.
//

#import "MQServiceToViewInterface.h"
#import <MeiQiaSDK/MQManager.h>
#import <MeiQiaSDK/MQAgent.h>

#pragma 该文件的作用是：开源聊天界面调用美洽 SDK 接口的中间层，目的是剥离开源界面中的美洽业务逻辑。这样就能让该聊天界面用于非美洽项目中，开发者只需要实现 `MQServiceToViewInterface` 中的方法，即可将自己项目的业务逻辑和该聊天界面对接。

@interface MQServiceToViewInterface()<MQManagerDelegate>

@end

@implementation MQServiceToViewInterface

+ (void)getServerHistoryMessagesWithMsgDate:(NSDate *)msgDate
                             messagesNumber:(NSInteger)messagesNumber
                            successDelegate:(id<MQServiceToViewInterfaceDelegate>)successDelegate
                              errorDelegate:(id<MQServiceToViewInterfaceErrorDelegate>)errorDelegate
{
    //将msgDate修改成GMT时区
    [MQManager getServerHistoryMessagesWithUTCMsgDate:msgDate messagesNumber:messagesNumber success:^(NSArray<MQMessage *> *messagesArray) {
        NSArray *toMessages = [MQServiceToViewInterface convertToChatViewMessageWithMQMessages:messagesArray];
        if (successDelegate) {
            if ([successDelegate respondsToSelector:@selector(didReceiveHistoryMessages:)]) {
                [successDelegate didReceiveHistoryMessages:toMessages];
            }
        }
    } failure:^(NSError *error) {
        NSLog(@"美洽SDK: 获取历史消息失败\nerror = %@", error);
        if (errorDelegate) {
            if ([errorDelegate respondsToSelector:@selector(getLoadHistoryMessageError)]) {
                [errorDelegate getLoadHistoryMessageError];
            }
        }
    }];
}

+ (void)getDatabaseHistoryMessagesWithMsgDate:(NSDate *)msgDate
                               messagesNumber:(NSInteger)messagesNumber
                                     delegate:(id<MQServiceToViewInterfaceDelegate>)delegate
{
    [MQManager getDatabaseHistoryMessagesWithMsgDate:msgDate messagesNumber:messagesNumber result:^(NSArray<MQMessage *> *messagesArray) {
        NSArray *toMessages = [MQServiceToViewInterface convertToChatViewMessageWithMQMessages:messagesArray];
        if (delegate) {
            if ([delegate respondsToSelector:@selector(didReceiveHistoryMessages:)]) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [delegate didReceiveHistoryMessages:toMessages];
                });
            }
        }
    }];
}

+ (NSArray *)convertToChatViewMessageWithMQMessages:(NSArray *)messagesArray {
    //将MQMessage转换成UI能用的Message类型
    NSMutableArray *toMessages = [[NSMutableArray alloc] init];
    for (MQMessage *fromMessage in messagesArray) {
        MQBaseMessage *toMessage;
        if (fromMessage.action == MQMessageActionMessage) {
            toMessage = [self convertToSendMessageWithMessage:fromMessage];
        } else {
            toMessage = [self convertToEventMessageWithMessage:fromMessage];
        }
        if (toMessage) {
            [toMessages addObject:toMessage];
        }
    }
    return toMessages;
}

+ (MQBaseMessage *)convertToEventMessageWithMessage:(MQMessage *)fromMessage {
    NSString *eventContent = @"";
    MQChatEventType eventType = MQChatEventTypeInitConversation;
    switch (fromMessage.action) {
        case MQMessageActionInitConversation:
        {
            eventContent = @"您进入了客服对话";
            eventType = MQChatEventTypeInitConversation;
            break;
        }
        case MQMessageActionAgentDidCloseConversation:
        {
            eventContent = @"客服结束了此条对话";
            eventType = MQChatEventTypeAgentDidCloseConversation;
            break;
        }
        case MQMessageActionEndConversationTimeout:
        {
            eventContent = @"对话超时，系统自动结束了对话";
            eventType = MQChatEventTypeEndConversationTimeout;
            break;
        }
        case MQMessageActionRedirect:
        {
            eventContent = @"您的对话被转接给了其他客服";
            eventType = MQChatEventTypeRedirect;
            break;
        }
        case MQMessageActionAgentInputting:
        {
            eventContent = @"客服正在输入...";
            eventType = MQChatEventTypeAgentInputting;
            break;
        }
        default:
            break;
    }
    if (eventContent.length == 0) {
        return nil;
    }
    MQEventMessage *toMessage = [[MQEventMessage alloc] initWithEventContent:eventContent eventType:eventType];
    toMessage.messageId = fromMessage.messageId;
    toMessage.date = fromMessage.createdOn;
    toMessage.content = eventContent;
    return toMessage;
}

+ (MQBaseMessage *)convertToSendMessageWithMessage:(MQMessage *)fromMessage {
    MQBaseMessage *toMessage;
    switch (fromMessage.contentType) {
        case MQMessageContentTypeText: {
            MQTextMessage *textMessage = [[MQTextMessage alloc] initWithContent:fromMessage.content];
            toMessage = textMessage;
            break;
        }
        case MQMessageContentTypeImage: {
            MQImageMessage *imageMessage = [[MQImageMessage alloc] initWithImagePath:fromMessage.content];
            toMessage = imageMessage;
            break;
        }
        case MQMessageContentTypeVoice: {
            MQVoiceMessage *voiceMessage = [[MQVoiceMessage alloc] initWithVoicePath:fromMessage.content];
            voiceMessage.isPlayed = false;
            toMessage = voiceMessage;
            break;
        }
        default:
            break;
    }
    toMessage.messageId = fromMessage.messageId;
    toMessage.date = fromMessage.createdOn;
    toMessage.userName = fromMessage.messageUserName;
    toMessage.userAvatarPath = fromMessage.messageAvatar;
    switch (fromMessage.sendStatus) {
        case MQMessageSendStatusSuccess:
            toMessage.sendStatus = MQChatMessageSendStatusSuccess;
            break;
        case MQMessageSendStatusFailed:
            toMessage.sendStatus = MQChatMessageSendStatusFailure;
            break;
        case MQMessageSendStatusSending:
            toMessage.sendStatus = MQChatMessageSendStatusSending;
            break;
        default:
            break;
    }
    switch (fromMessage.fromType) {
        case MQMessageFromTypeAgent:
        {
            toMessage.fromType = MQChatMessageIncoming;
            break;
        }
        case MQMessageFromTypeClient:
        {
            toMessage.fromType = MQChatMessageOutgoing;
            break;
        }
        default:
            break;
    }
    return toMessage;
}

+ (void)sendTextMessageWithContent:(NSString *)content
                         messageId:(NSString *)localMessageId
                          delegate:(id<MQServiceToViewInterfaceDelegate>)delegate;
{
    [MQManager sendTextMessageWithContent:content completion:^(MQMessage *sendedMessage, NSError *error) {
        [self didSendMessage:sendedMessage localMessageId:localMessageId delegate:delegate];
    }];
}

+ (void)sendImageMessageWithImage:(UIImage *)image
                        messageId:(NSString *)localMessageId
                         delegate:(id<MQServiceToViewInterfaceDelegate>)delegate;
{
    [MQManager sendImageMessageWithImage:image completion:^(MQMessage *sendedMessage, NSError *error) {
        [self didSendMessage:sendedMessage localMessageId:localMessageId delegate:delegate];
    }];
}

+ (void)sendAudioMessage:(NSData *)audio
               messageId:(NSString *)localMessageId
                delegate:(id<MQServiceToViewInterfaceDelegate>)delegate;
{
    [MQManager sendAudioMessage:audio completion:^(MQMessage *sendedMessage, NSError *error) {
        [self didSendMessage:sendedMessage localMessageId:localMessageId delegate:delegate];
    }];
}

+ (void)sendClientInputtingWithContent:(NSString *)content
{
    [MQManager sendClientInputtingWithContent:content];
}

+ (void)didSendMessage:(MQMessage *)sendedMessage
        localMessageId:(NSString *)localMessageId
              delegate:(id<MQServiceToViewInterfaceDelegate>)delegate
{
    if (delegate) {
        if ([delegate respondsToSelector:@selector(didSendMessageWithNewMessageId:oldMessageId:newMessageDate:sendStatus:)]) {
            MQChatMessageSendStatus sendStatus = MQChatMessageSendStatusSuccess;
            if (sendedMessage.sendStatus == MQMessageSendStatusFailed) {
                sendStatus = MQChatMessageSendStatusFailure;
            } else if (sendedMessage.sendStatus == MQMessageSendStatusSending) {
                sendStatus = MQChatMessageSendStatusSending;
            }
            [delegate didSendMessageWithNewMessageId:sendedMessage.messageId oldMessageId:localMessageId newMessageDate:sendedMessage.createdOn sendStatus:sendStatus];
        }
    }
}

+ (void)didSendFailedWithMessage:(MQMessage *)failedMessage
                  localMessageId:(NSString *)localMessageId
                           error:(NSError *)error
                        delegate:(id<MQServiceToViewInterfaceDelegate>)delegate
{
    NSLog(@"美洽SDK: 发送text消息失败\nerror = %@", error);
    if (delegate) {
        if ([delegate respondsToSelector:@selector(didSendMessageWithNewMessageId:oldMessageId:newMessageDate:sendStatus:)]) {
            [delegate didSendMessageWithNewMessageId:localMessageId oldMessageId:localMessageId newMessageDate:nil sendStatus:MQChatMessageSendStatusFailure];
        }
    }
}

+ (void)setClientOffline
{
    [MQManager setClientOffline];
}

+ (void)didTapMessageWithMessageId:(NSString *)messageId {
    [MQManager updateMessage:messageId toReadStatus:YES];
}

+ (NSString *)getCurrentAgentName {
    NSString *agentName = [MQManager getCurrentAgent].nickname;
    return agentName.length == 0 ? @"在线客服" : agentName;
}

+ (BOOL)isThereAgent {
    return [MQManager getCurrentAgent].agentId.length > 0;
}

+ (void)downloadMediaWithUrlString:(NSString *)urlString
                          progress:(void (^)(float progress))progressBlock
                        completion:(void (^)(NSData *mediaData, NSError *error))completion
{
    [MQManager downloadMediaWithUrlString:urlString progress:^(float progress) {
        if (progressBlock) {
            progressBlock(progress);
        }
    } completion:^(NSData *mediaData, NSError *error) {
        if (completion) {
            completion(mediaData, error);
        }
    }];
}

+ (void)removeMessageInDatabaseWithId:(NSString *)messageId
                           completion:(void (^)(BOOL, NSError *))completion
{
    [MQManager removeMessageInDatabaseWithId:messageId completion:completion];
}

+ (NSDictionary *)getCurrentClientInfo {
    return [MQManager getCurrentClientInfo];
}

+ (void)uploadClientAvatar:(UIImage *)avatarImage
                completion:(void (^)(BOOL success, NSError *error))completion
{
    [MQManager setClientAvatar:avatarImage completion:^(BOOL success, NSError *error) {
        [MQChatViewConfig sharedConfig].outgoingDefaultAvatarImage = avatarImage;
        [[NSNotificationCenter defaultCenter] postNotificationName:MQChatTableViewShouldRefresh object:avatarImage];
        if (completion) {
            completion(success, error);
        }
    }];
}

+ (void)setScheduleLogicWithRule:(MQChatScheduleRules)chatScheduleRule {
    MQScheduleRules rule;
    switch (chatScheduleRule) {
        case MQChatScheduleRulesNone:
            rule = MQScheduleRulesNone;
            break;
        case MQScheduleRulesGroup:
            rule = MQScheduleRulesGroup;
            break;
        case MQScheduleRulesEnterprise:
            rule = MQScheduleRulesEnterprise;
            break;
        default:
            break;
    }
    [MQManager setScheduleLogicWithRule:rule];
}

#pragma 实例方法
- (instancetype)init {
    if (self = [super init]) {
        
    }
    return self;
}

- (void)setClientOnlineWithCustomizedId:(NSString *)customizedId
                                success:(void (^)(BOOL completion, NSString *agentName, NSArray *receivedMessages))success
                 receiveMessageDelegate:(id<MQServiceToViewInterfaceDelegate>)receiveMessageDelegate
{
    self.serviceToViewDelegate = receiveMessageDelegate;
    [MQManager setClientOnlineWithCustomizedId:customizedId success:^(MQClientOnlineResult result, MQAgent *agent, NSArray<MQMessage *> *messages) {
        if (result == MQClientOnlineResultSuccess) {
            NSArray *toMessages = [MQServiceToViewInterface convertToChatViewMessageWithMQMessages:messages];
            success(true, agent.nickname, toMessages);
        } else if(result == MQClientOnlineResultNotScheduledAgent) {
            success(false, @"", nil);
        }
    } failure:^(NSError *error) {
        success(false, @"", nil);
    } receiveMessageDelegate:self];
}

- (void)setClientOnlineWithClientId:(NSString *)clientId
                            success:(void (^)(BOOL completion, NSString *agentName, NSArray *receivedMessages))success
             receiveMessageDelegate:(id<MQServiceToViewInterfaceDelegate>)receiveMessageDelegate
{
    self.serviceToViewDelegate = receiveMessageDelegate;
    if (!clientId || clientId.length == 0) {
        [MQManager setCurrentClientOnlineWithSuccess:^(MQClientOnlineResult result, MQAgent *agent, NSArray<MQMessage *> *messages) {
            if (result == MQClientOnlineResultSuccess) {
                NSArray *toMessages = [MQServiceToViewInterface convertToChatViewMessageWithMQMessages:messages];
                success(true, agent.nickname, toMessages);
            } else if(result == MQClientOnlineResultNotScheduledAgent) {
                success(false, @"", nil);
            }
        } failure:^(NSError *error) {
            success(false, @"初始化失败，请重新打开", nil);
        } receiveMessageDelegate:self];
        return ;
    }
    [MQManager setClientOnlineWithClientId:clientId success:^(MQClientOnlineResult result, MQAgent *agent, NSArray<MQMessage *> *messages) {
        if (result == MQClientOnlineResultSuccess) {
            NSArray *toMessages = [MQServiceToViewInterface convertToChatViewMessageWithMQMessages:messages];
            success(true, agent.nickname, toMessages);
        } else if(result == MQClientOnlineResultNotScheduledAgent) {
            success(false, @"", nil);
        }
    } failure:^(NSError *error) {
        success(false, @"初始化失败，请重新打开", nil);
    } receiveMessageDelegate:self];
}

+ (void)setScheduledAgentWithAgentId:(NSString *)agentId
                        agentGroupId:(NSString *)agentGroupId
{
    [MQManager setScheduledAgentWithAgentId:agentId agentGroupId:agentGroupId];
}

#pragma MQManagerDelegate
//webSocket收到消息的代理方法
- (void)didReceiveMQMessages:(NSArray<MQMessage *> *)messages {
    if (!self.serviceToViewDelegate) {
        return;
    }
    if (messages.count == 1 && [messages firstObject].action == MQMessageActionRedirect) {
        MQMessage *message = [messages firstObject];
        //客服被转接，给界面生成tipMessage
        NSString *agentName = message.agent.nickname ? message.agent.nickname : @"其他客服";
        NSString *tipsContent = [NSString stringWithFormat:@"接下来由 %@ 为您服务", agentName];
        if ([self.serviceToViewDelegate respondsToSelector:@selector(didReceiveTipsContent:)]) {
            [self.serviceToViewDelegate didReceiveTipsContent:tipsContent];
        }
        if ([self.serviceToViewDelegate respondsToSelector:@selector(didRedirectWithAgentName:)]) {
            [self.serviceToViewDelegate didRedirectWithAgentName:message.agent.nickname];
        }
    } else {
        NSArray *toMessages = [MQServiceToViewInterface convertToChatViewMessageWithMQMessages:messages];
        if ([self.serviceToViewDelegate respondsToSelector:@selector(didReceiveNewMessages:)]) {
            [self.serviceToViewDelegate didReceiveNewMessages:toMessages];
        }
    }
    
}



@end
