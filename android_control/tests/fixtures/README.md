These bounded HTML fixtures were retrieved from the official Mutopia Project on 2026-10-10 for catalog parser regression tests.

- catalog-list.html: https://www.mutopiaproject.org/cgibin/make-table.cgi?Instrument=Piano&searchingfor=&startat=0
- catalog-empty.html: https://www.mutopiaproject.org/cgibin/make-table.cgi?Instrument=Piano&searchingfor=zzzzzznotfound&startat=0

The application reads the live HTTPS catalog on user request. Fixtures are not a bundled song catalog and are not packaged as application assets. Each catalog entry retains its official MIDI URL, source page and license label. The app checks MIDI compatibility before caching or loading it into the FPGA score workflow.
