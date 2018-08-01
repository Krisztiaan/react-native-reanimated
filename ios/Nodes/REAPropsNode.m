#import "REAPropsNode.h"

#import "REANodesManager.h"
#import "REAStyleNode.h"
#import "REAModule.h"

#import <React/RCTLog.h>
#import <React/RCTUIManager.h>
#import "RCTComponentData.h"

@implementation REAPropsNode
{
  NSNumber *_connectedViewTag;
  NSString *_connectedViewName;
  NSMutableDictionary<NSString *, REANodeID> *_propsConfig;
}

- (instancetype)initWithID:(REANodeID)nodeID
                    config:(NSDictionary<NSString *,id> *)config
{
  if (self = [super initWithID:nodeID config:config]) {
    _propsConfig = config[@"props"];
  }
  return self;
}

- (void)connectToView:(NSNumber *)viewTag
             viewName:(NSString *)viewName
{
  _connectedViewTag = viewTag;
  _connectedViewName = viewName;
  [self dangerouslyRescheduleEvaluate];
}

- (void)disconnectFromView:(NSNumber *)viewTag
{
  _connectedViewTag = nil;
  _connectedViewName = nil;
}

- (id)evaluate
{
  NSMutableDictionary *nativeProps = [NSMutableDictionary new];
  NSMutableDictionary *jsProps = [NSMutableDictionary new];

  void (^addBlock)(NSString *key, id obj, BOOL * stop) = ^(NSString *key, id obj, BOOL * stop){
    if ([self.nodesManager.nativeProps containsObject:key]) {
      nativeProps[key] = obj;
    } else {
      jsProps[key] = obj;
    }
  };

  for (NSString *prop in _propsConfig) {
    REANode *propNode = [self.nodesManager findNodeByID:_propsConfig[prop]];

    if ([propNode isKindOfClass:[REAStyleNode class]]) {
      [[propNode value] enumerateKeysAndObjectsUsingBlock:addBlock];
    } else {
      addBlock(prop, [propNode value], nil);
    }
  }

  if (_connectedViewTag != nil) {
    if (nativeProps.count > 0) {
      [self.nodesManager.uiManager
       synchronouslyUpdateViewOnUIThread:_connectedViewTag
       viewName:_connectedViewName
       props:nativeProps];
    }
    if (jsProps.count > 0)
    {
      NSMutableDictionary<NSNumber *, RCTShadowView *> *shadowViewRegistry = [self.nodesManager.uiManager valueForKey:@"_shadowViewRegistry"];
      NSDictionary *componentDataByName = [self.nodesManager.uiManager valueForKey:@"_componentDataByName"];
      NSMapTable<RCTShadowView *, NSArray<NSString *> *> *shadowViewsWithUpdatedProps = [self.nodesManager.uiManager valueForKey:@"_shadowViewsWithUpdatedProps"];
      RCTShadowView *shadowView = shadowViewRegistry[_connectedViewTag];
      RCTComponentData *componentData = componentDataByName[_connectedViewName];
      RCTExecuteOnUIManagerQueue(^{
        [componentData setProps:jsProps forShadowView:shadowView];
        [self.nodesManager.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, UIView *> *viewRegistry) {
          UIView *view = viewRegistry[_connectedViewTag];
          [componentData setProps:jsProps forView:view];
        }];
        NSArray<NSString *> *newProps = [jsProps allKeys];
        NSArray<NSString *> *previousProps;
        if ((previousProps = [shadowViewsWithUpdatedProps objectForKey:shadowView]))
        {
          NSMutableSet *set = [NSMutableSet setWithArray:previousProps];
          [set addObjectsFromArray:newProps];
          newProps = [set allObjects];
        }
        
        [shadowViewsWithUpdatedProps setObject:newProps forKey:shadowView];
        [self.nodesManager.uiManager batchDidComplete];
      });
    }
  }

  return @(0);
}

- (void)update
{
  // Since we are updating nodes after detaching them from views there is a time where it's
  // possible that the view was disconnected and still receive an update, this is normal and we can
  // simply skip that update.
  if (!_connectedViewTag) {
    return;
  }

  // triger for side effect
  [self value];
}

@end

