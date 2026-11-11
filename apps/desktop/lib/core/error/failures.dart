/// Domain-level failure, carried in `Either<Failure, T>` (fpdart).
abstract class Failure {
  const Failure(this.message);
  final String message;
}

class UnexpectedFailure extends Failure {
  const UnexpectedFailure(super.message);
}

class ValidationFailure extends Failure {
  const ValidationFailure(super.message);
}

/// The destination file already exists. The screen offers overwrite
/// or rename; [destination] is the full path that was taken.
class FileExistsFailure extends Failure {
  const FileExistsFailure(this.destination) : super('File already exists');

  final String destination;
}
