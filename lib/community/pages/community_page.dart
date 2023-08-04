import 'dart:async';

// Flutter
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// External Packages
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lemmy_api_client/v3.dart';
import 'package:back_button_interceptor/back_button_interceptor.dart';

// Internal
import 'package:thunder/account/bloc/account_bloc.dart' as account_bloc;
import 'package:thunder/account/bloc/account_bloc.dart';
import 'package:thunder/community/bloc/anonymous_subscriptions_bloc.dart';
import 'package:thunder/community/bloc/community_bloc.dart';
import 'package:thunder/community/pages/create_post_page.dart';
import 'package:thunder/community/widgets/community_drawer.dart';
import 'package:thunder/community/widgets/post_card_list.dart';
import 'package:thunder/core/auth/bloc/auth_bloc.dart';
import 'package:thunder/core/enums/local_settings.dart';
import 'package:thunder/core/singletons/preferences.dart';
import 'package:thunder/shared/sort_picker.dart';
import 'package:thunder/thunder/bloc/thunder_bloc.dart';
import 'package:thunder/utils/constants.dart';

import '../../shared/gesture_fab.dart';

class CommunityPage extends StatefulWidget {
  final int? communityId;
  final String? communityName;
  final GlobalKey<ScaffoldState>? scaffoldKey;

  const CommunityPage({super.key, this.communityId, this.communityName, this.scaffoldKey});

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> with AutomaticKeepAliveClientMixin<CommunityPage> {
  @override
  bool get wantKeepAlive => true;

  SortType? sortType;
  IconData? sortTypeIcon;
  String? sortTypeLabel;
  CommunityBloc? currentCommunityBloc;
  bool _previousIsFabOpen = false;
  bool isFabOpen = false;
  bool _previousIsFabSummoned = true;
  bool isFabSummoned = true;
  bool enableFab = false;

  @override
  void initState() {
    super.initState();
    BackButtonInterceptor.add(_handleBack);
  }

  @override
  void dispose() {
    if (context.read<ThunderBloc>().state.isFabOpen) {
      context.read<ThunderBloc>().add(const OnFabToggle(false));
    }

    BackButtonInterceptor.remove(_handleBack);

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final ThunderState state = context.watch<ThunderBloc>().state;

    final theme = Theme.of(context);
    final bool isUserLoggedIn = context.read<AuthBloc>().state.isLoggedIn;
    enableFab = state.enableFeedsFab;
    bool enableBackToTop = state.enableBackToTop;
    bool enableSubscriptions = state.enableSubscriptions;
    bool enableChangeSort = state.enableChangeSort;
    bool enableRefresh = state.enableRefresh;
    bool enableDismissRead = state.enableDismissRead;
    bool enableNewPost = state.enableNewPost;

    if (state.isFabOpen != _previousIsFabOpen) {
      isFabOpen = state.isFabOpen;
      _previousIsFabOpen = isFabOpen;
    }
    if (state.isFabSummoned != _previousIsFabSummoned) {
      isFabSummoned = state.isFabSummoned;
      _previousIsFabSummoned = isFabSummoned;
    }

    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (context) => currentCommunityBloc = CommunityBloc()),
        BlocProvider(create: (context) => AnonymousSubscriptionsBloc()..add(GetSubscribedCommunitiesEvent())),
      ],
      child: BlocConsumer<CommunityBloc, CommunityState>(
        listenWhen: (previousState, currentState) {
          if (previousState.subscribedType != currentState.subscribedType) {
            context.read<account_bloc.AccountBloc>().add(account_bloc.GetAccountInformation());
          }

          if (previousState.sortType != currentState.sortType) {
            setState(() {
              sortType = currentState.sortType;
              final sortTypeItem = allSortTypeItems.firstWhere((sortTypeItem) => sortTypeItem.payload == currentState.sortType);
              sortTypeIcon = sortTypeItem.icon;
              sortTypeLabel = sortTypeItem.label;
            });
          }

          return true;
        },
        listener: (context, state) {
          if (state.status == CommunityStatus.failure) {
            SnackBar snackBar = SnackBar(
              content: Text(state.errorMessage ?? AppLocalizations.of(context)!.missingErrorMessage),
              behavior: SnackBarBehavior.floating,
            );
            WidgetsBinding.instance.addPostFrameCallback((timeStamp) => ScaffoldMessenger.of(context).showSnackBar(snackBar));
          }

          if (state.status == CommunityStatus.success && state.blockedCommunity != null) {
            SnackBar snackBar = SnackBar(
              content: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Successfully ${state.blockedCommunity?.blocked == true ? 'blocked' : 'unblocked'} ${state.blockedCommunity?.communityView.community.title}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (state.blockedCommunity?.blocked == true)
                    SizedBox(
                      height: 20,
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          ScaffoldMessenger.of(context).clearSnackBars();
                          context.read<CommunityBloc>().add(BlockCommunityEvent(communityId: state.blockedCommunity!.communityView.community.id, block: false));
                        },
                        icon: Icon(
                          Icons.undo_rounded,
                          color: theme.colorScheme.inversePrimary,
                        ),
                      ),
                    ),
                ],
              ),
              behavior: SnackBarBehavior.floating,
            );
            WidgetsBinding.instance.addPostFrameCallback((timeStamp) => ScaffoldMessenger.of(context).showSnackBar(snackBar));
          }
        },
        builder: (context, state) {
          return BlocListener<AuthBloc, AuthState>(
            listenWhen: (previous, current) {
              if (previous.account == null && current.account != null && previous.account?.id != current.account?.id) {
                context.read<CommunityBloc>().add(GetCommunityPostsEvent(reset: true, sortType: sortType));
                return true;
              }

              return false;
            },
            listener: (context, state) {},
            child: BlocConsumer<AnonymousSubscriptionsBloc, AnonymousSubscriptionsState>(
                listener: (c, s) {},
                builder: (c, subscriptionsState) {
                  return Scaffold(
                    key: widget.scaffoldKey,
                    appBar: AppBar(
                      title: Text(getCommunityName(state)),
                      centerTitle: false,
                      toolbarHeight: 70.0,
                      actions: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (state.communityId != null || state.communityName != null)
                              IconButton(
                                icon: Icon(
                                  switch (_getSubscriptionStatus(state, isUserLoggedIn, subscriptionsState)) {
                                    SubscribedType.notSubscribed => Icons.add_circle_outline_rounded,
                                    SubscribedType.pending => Icons.pending_outlined,
                                    SubscribedType.subscribed => Icons.remove_circle_outline_rounded,
                                    _ => Icons.add_circle_outline_rounded,
                                  },
                                  semanticLabel: (_getSubscriptionStatus(state, isUserLoggedIn, subscriptionsState) == SubscribedType.notSubscribed || state.subscribedType == null)
                                      ? AppLocalizations.of(context)!.subscribe
                                      : AppLocalizations.of(context)!.unsubscribe,
                                ),
                                tooltip: switch (_getSubscriptionStatus(state, isUserLoggedIn, subscriptionsState)) {
                                  SubscribedType.notSubscribed => AppLocalizations.of(context)!.subscribe,
                                  SubscribedType.pending => AppLocalizations.of(context)!.unsubscribePending,
                                  SubscribedType.subscribed => AppLocalizations.of(context)!.unsubscribe,
                                  _ => null,
                                },
                                onPressed: () {
                                  HapticFeedback.mediumImpact();
                                  _onSubscribeIconPressed(isUserLoggedIn, context, state);
                                },
                              ),
                            IconButton(
                                icon: Icon(Icons.refresh_rounded, semanticLabel: AppLocalizations.of(context)!.refresh),
                                onPressed: () {
                                  HapticFeedback.mediumImpact();
                                  context.read<AccountBloc>().add(GetAccountInformation());
                                  return context.read<CommunityBloc>().add(GetCommunityPostsEvent(
                                        reset: true,
                                        sortType: sortType,
                                        communityId: state.communityId,
                                        listingType: state.listingType,
                                        communityName: state.communityName,
                                      ));
                                }),
                            IconButton(
                                icon: Icon(sortTypeIcon, semanticLabel: AppLocalizations.of(context)!.sortBy),
                                tooltip: sortTypeLabel,
                                onPressed: () {
                                  HapticFeedback.mediumImpact();
                                  showSortBottomSheet(context, state);
                                }),
                            const SizedBox(width: 8.0),
                          ],
                        )
                      ],
                    ),
                    drawer: (widget.communityId != null || widget.communityName != null) ? null : const CommunityDrawer(),
                    floatingActionButton: enableFab
                        ? AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            switchInCurve: Curves.ease,
                            switchOutCurve: Curves.ease,
                            transitionBuilder: (child, animation) {
                              return SlideTransition(
                                position: Tween<Offset>(begin: const Offset(0, 0.2), end: const Offset(0, 0)).animate(animation),
                                child: child,
                              );
                            },
                            child: isFabSummoned
                                ? GestureFab(
                                    distance: 60,
                                    icon: Icon(
                                      Icons.clear_all_rounded,
                                      semanticLabel: AppLocalizations.of(context)!.dismissRead,
                                      size: 35,
                                    ),
                                    onPressed: () {
                                      HapticFeedback.lightImpact();
                                      context.read<ThunderBloc>().add(const OnDismissEvent(true));
                                    },
                                    children: [
                                      if (enableDismissRead)
                                        ActionButton(
                                          onPressed: () {
                                            HapticFeedback.lightImpact();
                                            context.read<ThunderBloc>().add(const OnDismissEvent(true));
                                          },
                                          title: AppLocalizations.of(context)!.dismissRead,
                                          icon: Icon(
                                            Icons.clear_all_rounded,
                                            semanticLabel: AppLocalizations.of(context)!.dismissRead,
                                          ),
                                        ),
                                      if (enableRefresh)
                                        ActionButton(
                                          onPressed: () {
                                            HapticFeedback.lightImpact();
                                            context.read<AccountBloc>().add(GetAccountInformation());
                                            return context.read<CommunityBloc>().add(GetCommunityPostsEvent(
                                                  reset: true,
                                                  sortType: sortType,
                                                  communityId: state.communityId,
                                                  listingType: state.listingType,
                                                  communityName: state.communityName,
                                                ));
                                          },
                                          title: AppLocalizations.of(context)!.refresh,
                                          icon: Icon(
                                            Icons.refresh_rounded,
                                            semanticLabel: AppLocalizations.of(context)!.refresh,
                                          ),
                                        ),
                                      if (enableChangeSort)
                                        ActionButton(
                                          onPressed: () {
                                            HapticFeedback.mediumImpact();
                                            showSortBottomSheet(context, state);
                                          },
                                          title: AppLocalizations.of(context)!.changeSort,
                                          icon: Icon(
                                            sortTypeIcon,
                                            semanticLabel: AppLocalizations.of(context)!.changeSort,
                                          ),
                                        ),
                                      if (widget.scaffoldKey != null && enableSubscriptions)
                                        ActionButton(
                                          onPressed: () => widget.scaffoldKey!.currentState!.openDrawer(),
                                          title: AppLocalizations.of(context)!.subscriptions,
                                          icon: Icon(
                                            Icons.people_rounded,
                                            semanticLabel: AppLocalizations.of(context)!.subscriptions,
                                          ),
                                        ),
                                      /*const ActionButton(
                            onPressed: (!state.useCompactView) => setPreferences(LocalSettings.useCompactView, value),,
                            title: state. ? "Large View" : "Compact View",
                            icon: state.useCompactView ? const Icon(Icons.crop_din_rounded) : Icon(Icons.crop_16_9_rounded),
                          ),*/
                                      if (enableBackToTop)
                                        ActionButton(
                                          onPressed: () {
                                            context.read<ThunderBloc>().add(OnScrollToTopEvent());
                                          },
                                          title: AppLocalizations.of(context)!.backToTop,
                                          icon: Icon(
                                            Icons.arrow_upward,
                                            semanticLabel: AppLocalizations.of(context)!.backToTop,
                                          ),
                                        ),
                                      if (state.communityId != null && enableNewPost || state.communityName != null && enableNewPost)
                                        ActionButton(
                                          onPressed: () {
                                            CommunityBloc communityBloc = context.read<CommunityBloc>();
                                            ThunderBloc thunderBloc = context.read<ThunderBloc>();
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (context) {
                                                  return MultiBlocProvider(
                                                    providers: [
                                                      BlocProvider<CommunityBloc>.value(value: communityBloc),
                                                      BlocProvider<ThunderBloc>.value(value: thunderBloc),
                                                    ],
                                                    child: CreatePostPage(communityId: state.communityId!, communityInfo: state.communityInfo),
                                                  );
                                                },
                                              ),
                                            );
                                          },
                                          title: AppLocalizations.of(context)!.createPost,
                                          icon: Icon(
                                            Icons.add,
                                            semanticLabel: AppLocalizations.of(context)!.createPost,
                                          ),
                                        ),
                                    ],
                                  )
                                : null,
                          )
                        : null,
                    body: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        SafeArea(child: _getBody(context, state)),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: isFabOpen
                              ? Listener(
                                  onPointerUp: (details) {
                                    context.read<ThunderBloc>().add(const OnFabToggle(false));
                                  },
                                  child: Container(
                                    color: theme.colorScheme.background.withOpacity(0.85),
                                  ),
                                )
                              : null,
                        ),
                        SizedBox(
                          height: 70,
                          width: 70,
                          child: GestureDetector(
                            onVerticalDragUpdate: (details) {
                              if (details.delta.dy < -5) {
                                context.read<ThunderBloc>().add(const OnFabSummonToggle(true));
                              }
                            },
                          ),
                        )
                      ],
                    ),
                  );
                }),
          );
        },
      ),
    );
  }

  Widget _getBody(BuildContext context, CommunityState state) {
    switch (state.status) {
      case CommunityStatus.initial:
        // communityId and communityName are mutually exclusive - only one of the two should be passed in
        context.read<CommunityBloc>().add(GetCommunityPostsEvent(reset: true, communityId: widget.communityId, communityName: widget.communityName));
        return const Center(child: CircularProgressIndicator());
      case CommunityStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case CommunityStatus.refreshing:
      case CommunityStatus.success:
      case CommunityStatus.failure:
        return PostCardList(
          subscribeType: state.subscribedType,
          postViews: state.postViews,
          listingType: state.communityId != null ? null : state.listingType,
          communityId: widget.communityId ?? state.communityId,
          communityName: widget.communityName ?? state.communityName,
          hasReachedEnd: state.hasReachedEnd,
          communityInfo: state.communityInfo,
          blockedCommunity: state.blockedCommunity,
          sortType: state.sortType,
          onScrollEndReached: () => context.read<CommunityBloc>().add(GetCommunityPostsEvent(communityId: widget.communityId)),
          onSaveAction: (int postId, bool save) => context.read<CommunityBloc>().add(SavePostEvent(postId: postId, save: save)),
          onVoteAction: (int postId, VoteType voteType) => context.read<CommunityBloc>().add(VotePostEvent(postId: postId, score: voteType)),
          onToggleReadAction: (int postId, bool read) => context.read<CommunityBloc>().add(MarkPostAsReadEvent(postId: postId, read: read)),
          taglines: state.taglines,
        );
      case CommunityStatus.empty:
        return Center(child: Text(AppLocalizations.of(context)!.noPosts));
    }
  }

  void showSortBottomSheet(BuildContext context, CommunityState state) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (builderContext) => SortPicker(
        title: AppLocalizations.of(context)!.sortOptions,
        onSelect: (selected) {
          setState(() {
            sortType = selected.payload;
            sortTypeIcon = selected.icon;
          });

          context.read<CommunityBloc>().add(
                GetCommunityPostsEvent(
                  sortType: selected.payload,
                  reset: true,
                  listingType: state.communityId != null ? null : state.listingType,
                  communityId: widget.communityId ?? state.communityId,
                ),
              );
        },
      ),
    );
  }

  String getCommunityName(CommunityState state) {
    if (state.status == CommunityStatus.initial || state.status == CommunityStatus.loading) {
      return '';
    }

    if (state.communityId != null || state.communityName != null) {
      return '';
    }

    return (state.listingType != null) ? (destinations.firstWhere((destination) => destination.listingType == state.listingType).label) : '';
  }

  FutureOr<bool> _handleBack(bool stopDefaultButtonEvent, RouteInfo info) async {
    if (currentCommunityBloc != null) {
      // This restricts back button handling to when we're already at the top level of navigation
      final canPop = Navigator.of(context).canPop();

      final prefs = (await UserPreferences.instance).sharedPreferences;
      final desiredPostListingType = PostListingType.values.byName(prefs.getString(LocalSettings.defaultFeedListingType.name) ?? DEFAULT_LISTING_TYPE.name);
      final currentPostListingType = currentCommunityBloc!.state.listingType;
      final currentCommunityId = currentCommunityBloc!.state.communityId;

      if (!canPop && (desiredPostListingType != currentPostListingType || currentCommunityId != null)) {
        currentCommunityBloc!.add(
          GetCommunityPostsEvent(
            sortType: currentCommunityBloc!.state.sortType,
            reset: true,
            listingType: desiredPostListingType,
            communityId: null,
          ),
        );

        return true;
      }
    }

    return false;
  }
}

SubscribedType? _getSubscriptionStatus(CommunityState state, bool isLoggedIn, AnonymousSubscriptionsState subscriptionsState) {
  if (isLoggedIn) {
    return state.subscribedType;
  }
  return subscriptionsState.ids.contains(state.communityId) ? SubscribedType.subscribed : SubscribedType.notSubscribed;
}

void _onSubscribeIconPressed(bool isUserLoggedIn, BuildContext context, CommunityState state) {
  if (isUserLoggedIn) {
    context.read<CommunityBloc>().add(
          ChangeCommunitySubsciptionStatusEvent(
            communityId: state.communityId!,
            follow: (state.subscribedType == null) ? true : (state.subscribedType == SubscribedType.notSubscribed ? true : false),
          ),
        );
    return;
  }
  CommunitySafe? community = state.communityInfo?.communityView.community;
  if (community == null) return;

  Set<int> currentSubscriptions = context.read<AnonymousSubscriptionsBloc>().state.ids;
  SnackBar snackBar = SnackBar(content: Text(AppLocalizations.of(context)!.subscribed));

  if (currentSubscriptions.contains(state.communityId)) {
    context.read<AnonymousSubscriptionsBloc>().add(DeleteSubscriptionsEvent(ids: {state.communityId!}));
    snackBar = SnackBar(content: Text(AppLocalizations.of(context)!.unsubscribed));
  } else {
    context.read<AnonymousSubscriptionsBloc>().add(AddSubscriptionsEvent(communities: {state.communityInfo!.communityView.community}));
  }

  ScaffoldMessenger.of(context).clearSnackBars();
  ScaffoldMessenger.of(context).showSnackBar(snackBar);
}
