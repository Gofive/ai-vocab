import 'package:ai_vocab/db_helper.dart';
import 'package:flutter/material.dart';

/// 迁移状态
enum MigrationStatus {
  notNeeded, // 不需要迁移
  pending, // 待迁移
  inProgress, // 迁移中
  completed, // 迁移完成
  failed, // 迁移失败
}

/// FSRS 迁移服务
///
/// 负责检测和执行 SM-2 到 FSRS 的数据迁移。
/// 在应用启动时检测是否需要迁移，并显示迁移进度提示。
///
/// _Requirements: 1.1, 2.4_
class MigrationService {
  static final MigrationService _instance = MigrationService._internal();
  factory MigrationService() => _instance;
  MigrationService._internal();

  final DBHelper _dbHelper = DBHelper();

  MigrationStatus _status = MigrationStatus.notNeeded;
  String _statusMessage = '';
  int _migratedCount = 0;
  int _totalCount = 0;

  MigrationStatus get status => _status;
  String get statusMessage => _statusMessage;
  int get migratedCount => _migratedCount;
  int get totalCount => _totalCount;
  double get progress => _totalCount > 0 ? _migratedCount / _totalCount : 0.0;

  /// 检查是否需要迁移
  ///
  /// 在应用启动时调用，检测数据库中是否有需要迁移的 SM-2 数据。
  ///
  /// _Requirements: 1.1_
  Future<bool> checkMigrationNeeded() async {
    try {
      final needsMigration = await _dbHelper.needsFSRSMigration();
      _status = needsMigration
          ? MigrationStatus.pending
          : MigrationStatus.notNeeded;
      return needsMigration;
    } catch (e) {
      _status = MigrationStatus.failed;
      _statusMessage = '检查迁移状态失败: $e';
      return false;
    }
  }

  /// 执行迁移
  ///
  /// 将 SM-2 数据迁移到 FSRS 格式。
  /// 迁移前会自动备份数据库，失败时自动回滚。
  ///
  /// [onProgress] - 进度回调，参数为 (已迁移数, 总数)
  ///
  /// _Requirements: 2.4_
  Future<bool> performMigration({
    void Function(int migrated, int total)? onProgress,
  }) async {
    if (_status == MigrationStatus.inProgress) {
      return false; // 防止重复执行
    }

    _status = MigrationStatus.inProgress;
    _statusMessage = '正在准备迁移...';

    try {
      // 获取迁移状态
      final migrationStatus = await _dbHelper.getMigrationStatus();
      _totalCount = migrationStatus['unmigrated'] ?? 0;
      _migratedCount = 0;

      if (_totalCount == 0) {
        _status = MigrationStatus.completed;
        _statusMessage = '无需迁移';
        return true;
      }

      _statusMessage = '正在备份数据库...';
      onProgress?.call(0, _totalCount);

      // 执行迁移
      _statusMessage = '正在迁移数据...';
      await _dbHelper.migrateToFSRS();

      // 更新状态
      _migratedCount = _totalCount;
      onProgress?.call(_migratedCount, _totalCount);

      _status = MigrationStatus.completed;
      _statusMessage = '迁移完成';
      return true;
    } catch (e) {
      _status = MigrationStatus.failed;
      _statusMessage = '迁移失败: $e';
      return false;
    }
  }

  /// 重置迁移状态
  void reset() {
    _status = MigrationStatus.notNeeded;
    _statusMessage = '';
    _migratedCount = 0;
    _totalCount = 0;
  }
}

/// 迁移对话框
///
/// 显示迁移进度和状态的对话框。
///
/// _Requirements: 2.4_
class MigrationDialog extends StatefulWidget {
  final VoidCallback? onComplete;
  final VoidCallback? onError;

  const MigrationDialog({super.key, this.onComplete, this.onError});

  @override
  State<MigrationDialog> createState() => _MigrationDialogState();
}

class _MigrationDialogState extends State<MigrationDialog> {
  final MigrationService _migrationService = MigrationService();
  bool _isComplete = false;
  bool _hasError = false;
  String _message = '正在检查数据...';
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    _startMigration();
  }

  Future<void> _startMigration() async {
    final success = await _migrationService.performMigration(
      onProgress: (migrated, total) {
        if (mounted) {
          setState(() {
            _progress = total > 0 ? migrated / total : 0.0;
            _message = '正在迁移数据 ($migrated/$total)...';
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isComplete = success;
        _hasError = !success;
        _message = success ? '迁移完成！' : _migrationService.statusMessage;
      });

      if (success) {
        widget.onComplete?.call();
      } else {
        widget.onError?.call();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            _hasError
                ? Icons.error_outline
                : (_isComplete ? Icons.check_circle : Icons.sync),
            color: _hasError
                ? Colors.red
                : (_isComplete ? Colors.green : Colors.blue),
          ),
          const SizedBox(width: 12),
          Text(_hasError ? '迁移失败' : (_isComplete ? '迁移完成' : '数据迁移')),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_message),
          if (!_isComplete && !_hasError) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _progress > 0 ? _progress : null),
            const SizedBox(height: 8),
            Text(
              '请勿关闭应用',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (_isComplete || _hasError)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('确定'),
          ),
      ],
    );
  }
}

/// 显示迁移对话框的辅助函数
///
/// 在应用启动时调用，检测是否需要迁移并显示对话框。
///
/// _Requirements: 1.1, 2.4_
Future<void> showMigrationDialogIfNeeded(BuildContext context) async {
  final migrationService = MigrationService();
  final needsMigration = await migrationService.checkMigrationNeeded();

  if (needsMigration && context.mounted) {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const MigrationDialog(),
    );
  }
}
