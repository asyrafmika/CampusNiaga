-- The USM email rule: exact domain match or an allowlisted email.
begin;
create extension if not exists pgtap with schema extensions;
select plan(16);

select ok(public.is_eligible_student_email('ali@student.usm.my', array['student.usm.my'], '{}'), 'accepts a student-domain email');
select ok(public.is_eligible_student_email('ALI@Student.USM.my', array['student.usm.my'], '{}'), 'ignores letter case');
select ok(public.is_eligible_student_email('  ali@student.usm.my  ', array['student.usm.my'], '{}'), 'ignores surrounding spaces');

select ok(not public.is_eligible_student_email('ali@gmail.com', array['student.usm.my'], '{}'), 'rejects gmail');
select ok(not public.is_eligible_student_email('staff@usm.my', array['student.usm.my'], '{}'), 'rejects the staff domain');
select ok(not public.is_eligible_student_email('ali@evilstudent.usm.my', array['student.usm.my'], '{}'), 'rejects a look-alike domain');
select ok(not public.is_eligible_student_email('ali@sub.student.usm.my', array['student.usm.my'], '{}'), 'rejects a sub-domain');
select ok(not public.is_eligible_student_email('ali@student.usm.my.example.com', array['student.usm.my'], '{}'), 'rejects a domain that only starts the same');
select ok(not public.is_eligible_student_email('student.usm.my', array['student.usm.my'], '{}'), 'rejects text without an @');
select ok(not public.is_eligible_student_email('@student.usm.my', array['student.usm.my'], '{}'), 'rejects an empty name before the @');
select ok(not public.is_eligible_student_email('a@b@student.usm.my', array['student.usm.my'], '{}'), 'rejects two @ signs');
select ok(not public.is_eligible_student_email('', array['student.usm.my'], '{}'), 'rejects an empty email');
select ok(not public.is_eligible_student_email(null, array['student.usm.my'], '{}'), 'rejects a missing email');

select ok(public.is_eligible_student_email('Examiner@Gmail.com', array['student.usm.my'], array['examiner@gmail.com']), 'accepts an allowlisted email of any domain');
select ok(public.is_eligible_student_email('ali@usm.edu.test', array['usm.edu.test'], '{}'), 'uses the configured domain');
select ok(not public.is_eligible_student_email('ali@student.usm.my', array['usm.edu.test'], '{}'), 'does not hard-code the default domain');

select * from finish();
rollback;
