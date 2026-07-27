#include <libical/ical.h>
#include <stdio.h>

int main(int argc, char **argv) {
    if (argc != 5) {
        fprintf(stderr, "usage: oracle RULE DTSTART FROM TO\n");
        return 2;
    }
    struct icalrecurrencetype *rule =
        icalrecurrencetype_new_from_string(argv[1]);
    if (rule == NULL) {
        return 3;
    }
    struct icaltimetype start = icaltime_from_string(argv[2]);
    struct icaltimetype from = icaltime_from_string(argv[3]);
    struct icaltimetype to = icaltime_from_string(argv[4]);
    icalrecur_iterator *iterator = icalrecur_iterator_new(rule, start);
    if (iterator == NULL) {
        icalrecurrencetype_unref(rule);
        return 3;
    }
    for (;;) {
        struct icaltimetype next = icalrecur_iterator_next(iterator);
        if (icaltime_is_null_time(next) || icaltime_compare(next, to) >= 0) {
            break;
        }
        if (icaltime_compare(next, from) >= 0) {
            puts(icaltime_as_ical_string(next));
        }
    }
    icalrecur_iterator_free(iterator);
    icalrecurrencetype_unref(rule);
    return 0;
}
