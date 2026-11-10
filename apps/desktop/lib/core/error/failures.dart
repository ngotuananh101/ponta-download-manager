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
