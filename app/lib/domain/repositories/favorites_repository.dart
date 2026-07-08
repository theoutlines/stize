import '../models/favorite_stop.dart';

abstract class FavoritesRepository {
  Future<List<FavoriteStop>> getFavorites();
  Future<void> add(FavoriteStop stop);
  Future<void> remove(String stopId);
  Future<bool> isFavorite(String stopId);
}
