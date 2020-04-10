import 'dart:collection';
import 'dart:typed_data';
import 'package:Tether/domain/rooms/events/selectors.dart';
import 'package:dart_json_mapper/dart_json_mapper.dart';
import 'package:Tether/domain/rooms/events/model.dart';
import 'package:flutter/foundation.dart';

@jsonSerializable
class Avatar {
  final String uri;
  final String url;
  final String type;
  final Uint8List data;

  const Avatar({
    this.uri,
    this.url,
    this.type,
    this.data,
  });
  Avatar copyWith({
    uri,
    url,
    type,
    data,
  }) {
    return Avatar(
      uri: uri ?? this.uri,
      url: url ?? this.url,
      type: type ?? this.type,
      data: data ?? this.data,
    );
  }

  @override
  String toString() {
    return '{\n' +
        'uri: $uri,\n' +
        'url: $url,\b' +
        'type: $type,\n' +
        'data: $data,\n' +
        '}';
  }
}

@jsonSerializable
class Room {
  final String id;
  final String name;
  final String homeserver;
  final Avatar avatar;
  final String topic;
  final bool direct;
  final bool syncing;
  final bool sending;
  final String startTime;
  final String endTime;
  final int lastUpdate;

  // Event lists
  final List<Event> state;
  final List<Message> messages;
  final Event draft;

  const Room({
    this.id,
    this.name = 'New Room',
    this.homeserver,
    this.avatar,
    this.topic = '',
    this.direct = false,
    this.syncing = false,
    this.sending = false,
    this.messages = const [],
    this.state = const [],
    this.lastUpdate = 0,
    this.draft,
    this.startTime,
    this.endTime,
  });

  Room copyWith({
    id,
    name,
    homeserver,
    avatar,
    topic,
    lastUpdate,
    direct,
    syncing,
    sending,
    state,
    events,
    messages,
    startTime,
    endTime,
    draft,
  }) {
    return Room(
      id: id ?? this.id,
      name: name ?? this.name,
      homeserver: homeserver ?? this.homeserver,
      avatar: avatar ?? this.avatar,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      direct: direct ?? this.direct,
      sending: sending ?? this.sending,
      syncing: syncing ?? this.syncing,
      state: state ?? this.state,
      messages: messages ?? this.messages,
      draft: draft ?? this.draft,
    );
  }

  Room fromMessageEvents(
    List<Event> messageEvents, {
    String startTime,
    String endTime,
  }) {
    int lastUpdate = this.lastUpdate;
    List<Event> existingMessages =
        this.messages.isNotEmpty ? List<Event>.from(this.messages) : [];
    List<Event> messages = messageEvents ?? [];

    // Converting only message events
    final newMessages =
        messages.where((event) => event.type == 'm.room.message').toList();

    // See if the newest message has a greater timestamp
    if (newMessages.isNotEmpty && messages[0].timestamp > lastUpdate) {
      lastUpdate = messages[0].timestamp;
    }

    // Combine current and existing messages on unique ids
    final combinedMessagesMap = HashMap.fromIterable(
      [existingMessages, newMessages].expand(
        (sublist) => sublist.map(
          (event) => event is Message ? event : Message.fromEvent(event),
        ),
      ),
      key: (message) => message.id,
      value: (message) => message,
    );

    // Confirm sorting the messages here, I think this should be done by the
    final combinedMessages = List<Message>.from(combinedMessagesMap.values);

    // latestMessages(List<Message>.from(combinedMessagesMap.values));

    // Add to room
    return this.copyWith(
      messages: combinedMessages,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
    );
  }

  // Find details of room based on state events
  // follows spec naming priority and thumbnail downloading
  Room fromStateEvents(
    List<Event> stateEvents, {
    String originDEBUG,
    String username,
    int limit,
  }) {
    String name;
    Avatar avatar;
    String topic;
    int namePriority = 4;
    int lastUpdate = this.lastUpdate;
    List<Event> cachedStateEvents = List<Event>();

    try {
      stateEvents.forEach((event) {
        lastUpdate =
            event.timestamp > lastUpdate ? event.timestamp : lastUpdate;

        switch (event.type) {
          case 'm.room.name':
            namePriority = 1;
            name = event.content['name'];
            break;
          case 'm.room.topic':
            topic = event.content['topic'];
            break;
          case 'm.room.canonical_alias':
            if (namePriority > 2) {
              namePriority = 2;
              name = event.content['alias'];
            }
            break;
          case 'm.room.aliases':
            if (namePriority > 3) {
              namePriority = 3;
              name = event.content['aliases'][0];
            }
            break;
          case 'm.room.avatar':
            final avatarFile = event.content['thumbnail_file'];
            if (avatarFile == null) {
              // Keep previous avatar url until the new uri is fetched
              avatar = this.avatar != null ? this.avatar : Avatar();
              avatar = avatar.copyWith(
                uri: event.content['url'],
              );
            }
            break;
          case 'm.room.member':
            if (this.direct && event.content['displayname'] != username) {
              name = event.content['displayname'];
            }
            break;
          default:
            break;
        }
      });
    } catch (error) {
      print('[fromStateEvents] error $error');
    }

    return this.copyWith(
      name: name ?? this.name ?? 'New Room',
      avatar: avatar ?? this.avatar,
      topic: topic ?? this.topic,
      lastUpdate: lastUpdate > 0 ? lastUpdate : this.lastUpdate,
      state: cachedStateEvents,
    );
  }

  Room fromSync({
    String username,
    Map<String, dynamic> json,
  }) {
    // contains message events
    final List<dynamic> rawTimelineEvents = json['timeline']['events'];
    final List<dynamic> rawStateEvents = json['state']['events'];

    // print(json['summary']);
    // print(json['ephemeral']);
    // Check for message events
    // print('TIMELINE OUTPUT ${json['timeline']}');
    // TODO: final List<dynamic> rawAccountDataEvents = json['account_data']['events'];
    // TODO: final List<dynamic> rawEphemeralEvents = json['ephemeral']['events'];

    final List<Event> stateEvents =
        rawStateEvents.map((event) => Event.fromJson(event)).toList();

    final List<Event> messageEvents =
        rawTimelineEvents.map((event) => Event.fromJson(event)).toList();

    return this
        .fromStateEvents(
          stateEvents,
          username: username,
          originDEBUG: '[fetchSync]',
        )
        .fromMessageEvents(
          messageEvents,
        );
  }

  @override
  String toString() {
    return '{\n' +
        'id: $id,\n' +
        'name: $name,\n' +
        'homeserver: $homeserver,\n' +
        'direct: $direct,\n' +
        'syncing: $syncing,\n' +
        'state: $state,\n' +
        'avatar: $avatar,\n' +
        '}';
  }
}
